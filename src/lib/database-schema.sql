-- InvoChat - Complete Database Schema
-- Version: 2.0
-- Description: This script sets up the entire database from scratch,
-- including tables, roles, functions, triggers, and security policies.
-- It incorporates all fixes for data integrity, security, and performance.

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Define custom types
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
END
$$;

-- Create sequences for human-readable IDs first
CREATE SEQUENCE IF NOT EXISTS public.sales_sale_number_seq;
CREATE SEQUENCE IF NOT EXISTS public.purchase_orders_po_number_seq;


-- Create core tables
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_companies_created_at ON public.companies(created_at);

CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    barcode text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    UNIQUE(company_id, sku)
);
CREATE INDEX IF NOT EXISTS idx_products_company_sku ON public.products(company_id, sku);

CREATE TABLE IF NOT EXISTS public.locations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    address text,
    is_default boolean DEFAULT false,
    created_at timestamptz DEFAULT now(),
    UNIQUE(company_id, name)
);

CREATE TABLE IF NOT EXISTS public.inventory (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
    quantity integer NOT NULL DEFAULT 0,
    cost bigint NOT NULL DEFAULT 0, -- In cents
    price bigint, -- In cents
    landed_cost bigint, -- In cents
    on_order_quantity integer NOT NULL DEFAULT 0,
    last_sold_date date,
    version integer NOT NULL DEFAULT 1,
    deleted_at timestamptz,
    deleted_by uuid REFERENCES auth.users(id),
    source_platform text,
    external_product_id text,
    external_variant_id text,
    external_quantity integer,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    CONSTRAINT fk_company FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    UNIQUE(company_id, product_id, location_id),
    CONSTRAINT inventory_quantity_non_negative CHECK ((quantity >= 0)),
    CONSTRAINT on_order_quantity_non_negative CHECK ((on_order_quantity >= 0))
);
CREATE INDEX IF NOT EXISTS idx_inventory_product_id ON public.inventory(product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_location_id ON public.inventory(location_id);
CREATE INDEX IF NOT EXISTS idx_inventory_deleted_at ON public.inventory(company_id, deleted_at);

CREATE TABLE IF NOT EXISTS public.vendors (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    vendor_name text NOT NULL,
    contact_info text,
    address text,
    terms text,
    account_number text,
    created_at timestamptz DEFAULT now(),
    UNIQUE(company_id, vendor_name)
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.vendors(id),
    po_number text NOT NULL,
    status text,
    order_date date,
    expected_date date,
    total_amount bigint,
    tax_amount bigint,
    shipping_cost bigint,
    notes text,
    requires_approval boolean DEFAULT false,
    approved_by uuid REFERENCES auth.users(id),
    approved_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, po_number)
);
ALTER TABLE public.purchase_orders ALTER COLUMN po_number SET DEFAULT 'PO-' || TO_CHAR(nextval('purchase_orders_po_number_seq'), 'FM000000');

CREATE TABLE IF NOT EXISTS public.purchase_order_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    po_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    quantity_ordered integer NOT NULL,
    quantity_received integer DEFAULT 0 NOT NULL,
    unit_cost bigint, -- In cents
    tax_rate numeric(5,4),
    UNIQUE(po_id, product_id)
);

CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text,
    external_id text,
    customer_name text NOT NULL,
    email text,
    status text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    UNIQUE(company_id, email)
);

CREATE TABLE IF NOT EXISTS public.sales (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sale_number text NOT NULL,
    customer_id uuid REFERENCES public.customers(id),
    customer_name text,
    customer_email text,
    total_amount bigint NOT NULL,
    tax_amount bigint,
    payment_method text,
    notes text,
    created_at timestamptz DEFAULT now(),
    created_by uuid REFERENCES auth.users(id),
    external_id text,
    UNIQUE(company_id, sale_number)
);
ALTER TABLE public.sales ALTER COLUMN sale_number SET DEFAULT 'SALE-' || TO_CHAR(nextval('sales_sale_number_seq'), 'FM000000');

CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    quantity integer NOT NULL,
    unit_price bigint NOT NULL,
    cost_at_time bigint, -- Snapshot of cost at time of sale
    UNIQUE(sale_id, product_id)
);

CREATE TABLE IF NOT EXISTS public.reorder_rules (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL,
    location_id uuid REFERENCES public.locations(id) ON DELETE CASCADE,
    rule_type text DEFAULT 'manual',
    min_stock integer,
    max_stock integer,
    reorder_quantity integer,
    CONSTRAINT fk_reorder_rules_product FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE,
    UNIQUE(company_id, product_id, location_id)
);

CREATE TABLE IF NOT EXISTS public.supplier_catalogs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    supplier_id uuid NOT NULL REFERENCES public.vendors(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    supplier_sku text,
    unit_cost bigint NOT NULL,
    moq integer DEFAULT 1,
    lead_time_days integer,
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT now(),
    UNIQUE(supplier_id, product_id)
);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL,
    location_id uuid,
    created_at timestamptz DEFAULT now() NOT NULL,
    created_by uuid REFERENCES auth.users(id),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer,
    related_id uuid,
    notes text,
    CONSTRAINT fk_ledger_product FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE,
    CONSTRAINT fk_ledger_location FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_company_product_date ON public.inventory_ledger(company_id, product_id, created_at DESC);

-- Other tables (integrations, audit, etc.)
CREATE TABLE IF NOT EXISTS public.integrations (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
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

CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id),
    company_id uuid REFERENCES public.companies(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.user_feedback (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback text NOT NULL, -- 'helpful' or 'unhelpful'
    created_at timestamptz DEFAULT now() NOT NULL
);

-- Helper functions and triggers
CREATE OR REPLACE FUNCTION public.bump_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

-- Apply the updated_at trigger to relevant tables
DO $$
DECLARE
    t_name text;
BEGIN
    FOR t_name IN
        SELECT table_name FROM information_schema.columns WHERE column_name = 'updated_at' AND table_schema = 'public'
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS handle_updated_at ON public.%I', t_name);
        EXECUTE format('CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at()', t_name);
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.increment_version()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
   NEW.version = OLD.version + 1;
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS handle_inventory_update ON public.inventory;
CREATE TRIGGER handle_inventory_update BEFORE UPDATE ON public.inventory FOR EACH ROW EXECUTE PROCEDURE public.increment_version();


-- This is the correct, secure way to handle new user sign-ups in Supabase.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_company_id uuid;
  user_role public.user_role;
  company_name_text text;
BEGIN
  company_name_text := trim(new.raw_user_meta_data->>'company_name');
  IF company_name_text IS NULL OR company_name_text = '' THEN
    RAISE EXCEPTION 'Company name cannot be empty.';
  END IF;

  INSERT INTO public.companies (name)
  VALUES (company_name_text)
  RETURNING id INTO new_company_id;

  user_role := 'Owner';
  
  -- Use the built-in admin function to update the user's metadata securely.
  -- This avoids trying to modify the auth.users table directly.
  PERFORM auth.admin_update_user(
      new.id,
      jsonb_build_object(
          'app_metadata', jsonb_build_object(
              'company_id', new_company_id,
              'role', user_role
          )
      )
  );
  
  RETURN new;
END;
$$;

-- Set up the trigger on the auth.users table.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- This helper function allows us to get the company_id from the JWT in RLS policies.
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (auth.jwt()->'app_metadata'->>'company_id')::uuid
$$;

-- Function to record a sale and atomically update inventory.
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
  p_company_id   uuid,
  p_user_id      uuid,
  p_sale_items   jsonb,
  p_customer_name text     DEFAULT NULL,
  p_customer_email text    DEFAULT NULL,
  p_payment_method text    DEFAULT 'other',
  p_notes         text     DEFAULT NULL,
  p_external_id   text     DEFAULT NULL
)
RETURNS public.sales
LANGUAGE plpgsql
AS $$
DECLARE
  new_sale         public.sales;
  v_customer_id    uuid;
  total_amount     bigint;
  tax_rate         numeric;
  tax_amount       bigint;
  item_rec         record;
  inv_rec          record;
  tmp              text := 'sale_items_tmp_'||replace(gen_random_uuid()::text,'-','');
BEGIN
  -- 1. Create a temporary table for the sale items. This is robust and safe.
  EXECUTE format($fmt$
    CREATE TEMP TABLE %I (
      product_id   uuid,
      location_id  uuid,
      quantity     integer,
      unit_price   integer,
      cost_at_time integer
    ) ON COMMIT DROP
  $fmt$, tmp);

  -- 2. Populate the temp table, fetching the current cost at the same time.
  EXECUTE format($fmt$
    INSERT INTO %I (product_id, location_id, quantity, unit_price, cost_at_time)
    SELECT
      (j->>'product_id')::uuid,
      (j->>'location_id')::uuid,
      (j->>'quantity')::int,
      (j->>'unit_price')::int,
      i.cost
    FROM jsonb_array_elements($1) AS j
    JOIN public.inventory i ON i.product_id = (j->>'product_id')::uuid AND i.location_id = (j->>'location_id')::uuid AND i.company_id = $2
  $fmt$, tmp)
  USING p_sale_items, p_company_id;

  -- 3. Perform stock checks using the temporary table data.
  FOR item_rec IN EXECUTE format('SELECT * FROM %I', tmp) LOOP
    SELECT * INTO inv_rec FROM public.inventory 
    WHERE company_id = p_company_id AND product_id = item_rec.product_id AND location_id = item_rec.location_id FOR UPDATE;
    
    IF NOT FOUND OR inv_rec.quantity < item_rec.quantity THEN
      RAISE EXCEPTION 'Insufficient stock for product % at location %.', item_rec.product_id, item_rec.location_id;
    END IF;
  END LOOP;

  -- 4. Calculate total amount.
  EXECUTE format('SELECT SUM(quantity * unit_price) FROM %I', tmp) INTO total_amount;

  -- 5. Upsert customer record if an email is provided.
  IF p_customer_email IS NOT NULL THEN
    INSERT INTO public.customers(company_id, customer_name, email)
    VALUES (p_company_id, p_customer_name, p_customer_email)
    ON CONFLICT (company_id, email) DO UPDATE SET customer_name = EXCLUDED.customer_name
    RETURNING id INTO v_customer_id;
  END IF;

  -- 6. Insert the main sales record.
  INSERT INTO public.sales (company_id, customer_id, customer_name, customer_email, total_amount, payment_method, notes, created_by, external_id)
  VALUES (p_company_id, v_customer_id, p_customer_name, p_customer_email, total_amount, p_payment_method, p_notes, p_user_id, p_external_id)
  RETURNING * INTO new_sale;

  -- 7. Insert sale items and update inventory atomically.
  FOR item_rec IN EXECUTE format('SELECT * FROM %I', tmp) LOOP
    INSERT INTO public.sale_items (sale_id, company_id, product_id, quantity, unit_price, cost_at_time)
    VALUES (new_sale.id, p_company_id, item_rec.product_id, item_rec.quantity, item_rec.unit_price, item_rec.cost_at_time);

    UPDATE public.inventory
    SET quantity = quantity - item_rec.quantity, last_sold_date = CURRENT_DATE
    WHERE company_id = p_company_id AND product_id = item_rec.product_id AND location_id = item_rec.location_id;

    INSERT INTO public.inventory_ledger (company_id, product_id, location_id, change_type, quantity_change, new_quantity, related_id, notes, created_by)
    VALUES (p_company_id, item_rec.product_id, item_rec.location_id, 'sale', -item_rec.quantity, 
            (SELECT quantity FROM public.inventory WHERE product_id = item_rec.product_id AND location_id = item_rec.location_id AND company_id = p_company_id), 
            new_sale.id, 'Sale #' || new_sale.sale_number, p_user_id);
  END LOOP;

  RETURN new_sale;
END;
$$;


-- Enable Row-Level Security on all tables.
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reorder_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_catalogs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;

-- Create RLS Policies
DROP POLICY IF EXISTS "Enable read access for own company" ON public.companies;
CREATE POLICY "Enable read access for own company" ON public.companies FOR SELECT USING (id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access for own company" ON public.products;
CREATE POLICY "Enable all access for own company" ON public.products FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access for own company" ON public.locations;
CREATE POLICY "Enable all access for own company" ON public.locations FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access for own company" ON public.inventory;
CREATE POLICY "Enable all access for own company" ON public.inventory FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access for own company" ON public.vendors;
CREATE POLICY "Enable all access for own company" ON public.vendors FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access for own company" ON public.purchase_orders;
CREATE POLICY "Enable all access for own company" ON public.purchase_orders FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access for own company" ON public.purchase_order_items;
CREATE POLICY "Enable all access for own company" ON public.purchase_order_items FOR ALL USING (po_id IN (SELECT id FROM public.purchase_orders));

DROP POLICY IF EXISTS "Enable all access for own company" ON public.customers;
CREATE POLICY "Enable all access for own company" ON public.customers FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access for own company" ON public.sales;
CREATE POLICY "Enable all access for own company" ON public.sales FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access for own company" ON public.sale_items;
CREATE POLICY "Enable all access for own company" ON public.sale_items FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access for own company" ON public.reorder_rules;
CREATE POLICY "Enable all access for own company" ON public.reorder_rules FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access for own company" ON public.supplier_catalogs;
CREATE POLICY "Enable all access for own company" ON public.supplier_catalogs FOR ALL USING (supplier_id IN (SELECT id FROM public.vendors WHERE company_id = auth.company_id()));

DROP POLICY IF EXISTS "Enable all access for own company" ON public.inventory_ledger;
CREATE POLICY "Enable all access for own company" ON public.inventory_ledger FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access for own company" ON public.integrations;
CREATE POLICY "Enable all access for own company" ON public.integrations FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access for own company" ON public.audit_log;
CREATE POLICY "Enable all access for own company" ON public.audit_log FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access for own company" ON public.user_feedback;
CREATE POLICY "Enable all access for own company" ON public.user_feedback FOR ALL USING (company_id = auth.company_id());


-- Storage policies
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow public read access to public_assets" ON storage.objects;
CREATE POLICY "Allow public read access to public_assets" ON storage.objects FOR SELECT USING (bucket_id = 'public_assets');


-- Grant permissions
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public to authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
