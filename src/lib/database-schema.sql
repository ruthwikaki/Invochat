
-- InvoChat - Production-Grade Database Schema v4.0
-- This schema has been completely rewritten to address critical business logic flaws,
-- enforce data integrity, and implement SMB-safe financial guardrails.

-- Enable UUID extension for primary keys
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Define custom types
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'po_status') THEN
        CREATE TYPE public.po_status AS ENUM ('draft', 'sent', 'partial', 'received', 'cancelled', 'pending_approval');
    END IF;
END
$$;

-- Create sequences before they are referenced
CREATE SEQUENCE IF NOT EXISTS public.sales_sale_number_seq;
CREATE SEQUENCE IF NOT EXISTS public.purchase_orders_po_number_seq;


-------------------------------------------
-- CORE TABLES
-------------------------------------------

CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_companies_created_at ON public.companies(created_at);

-- No longer creating a public.users table. We will use auth.users directly.

CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    barcode text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, sku)
);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);

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
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
    quantity integer NOT NULL DEFAULT 0,
    cost bigint NOT NULL DEFAULT 0, -- In cents
    price bigint, -- In cents
    landed_cost bigint, -- In cents
    on_order_quantity integer NOT NULL DEFAULT 0,
    last_sold_date date,
    version integer NOT NULL DEFAULT 1,
    source_platform text,
    external_product_id text,
    external_variant_id text,
    external_quantity integer,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(product_id, location_id),
    CONSTRAINT inventory_quantity_non_negative CHECK ((quantity >= 0)),
    CONSTRAINT on_order_quantity_non_negative CHECK ((on_order_quantity >= 0))
);
CREATE INDEX IF NOT EXISTS idx_inventory_product_id ON public.inventory(product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_location_id ON public.inventory(location_id);

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

CREATE TABLE IF NOT EXISTS public.sales (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sale_number text NOT NULL,
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
CREATE INDEX IF NOT EXISTS idx_sales_created_at ON public.sales(company_id, created_at);
CREATE INDEX IF NOT EXISTS idx_sales_customer_email ON public.sales(company_id, customer_email);

CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid NOT NULL REFERENCES public.locations(id) ON DELETE RESTRICT,
    quantity integer NOT NULL,
    unit_price bigint NOT NULL,
    cost_at_time bigint,
    UNIQUE(sale_id, product_id, location_id)
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.vendors(id),
    po_number text NOT NULL,
    status public.po_status DEFAULT 'draft',
    order_date date DEFAULT CURRENT_DATE,
    expected_date date,
    total_amount bigint,
    tax_amount bigint,
    shipping_cost bigint,
    notes text,
    requires_approval boolean default false,
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
    unit_cost bigint,
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

-------------------------------------------
-- SUPPLEMENTAL & CONFIG TABLES
-------------------------------------------

CREATE TABLE IF NOT EXISTS public.reorder_rules (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    location_id uuid REFERENCES public.locations(id) ON DELETE CASCADE,
    rule_type text DEFAULT 'manual',
    min_stock integer,
    max_stock integer,
    reorder_quantity integer,
    UNIQUE(product_id, location_id)
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
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid REFERENCES public.locations(id) ON DELETE RESTRICT,
    created_at timestamptz DEFAULT now() NOT NULL,
    created_by uuid REFERENCES auth.users(id),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer,
    related_id uuid,
    notes text
);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_location ON public.inventory_ledger(product_id, location_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier numeric(10,2) NOT NULL DEFAULT 3,
    high_value_threshold bigint NOT NULL DEFAULT 100000,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric(5,4) DEFAULT 0,
    custom_rules jsonb,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);

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
    feedback text NOT NULL,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role text NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric(3,2),
    assumptions text[],
    created_at timestamptz DEFAULT now(),
    is_error boolean DEFAULT false
);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id_created_at ON public.messages(conversation_id, created_at);


-------------------------------------------
-- TRIGGERS & AUTOMATION
-------------------------------------------

-- Function to automatically update the 'updated_at' timestamp on a row
CREATE OR REPLACE FUNCTION public.bump_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;

-- Function to automatically increment the version on inventory updates
CREATE OR REPLACE FUNCTION public.increment_version()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
   NEW.version = OLD.version + 1;
   RETURN NEW;
END;
$$;

-- Apply updated_at and version triggers to relevant tables
DROP TRIGGER IF EXISTS handle_inventory_update ON public.inventory;
CREATE TRIGGER handle_inventory_update
BEFORE UPDATE ON public.inventory
FOR EACH ROW EXECUTE PROCEDURE public.increment_version();

-- Apply updated_at triggers
CREATE TRIGGER handle_products_update BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
CREATE TRIGGER handle_locations_update BEFORE UPDATE ON public.locations FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
CREATE TRIGGER handle_vendors_update BEFORE UPDATE ON public.vendors FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
CREATE TRIGGER handle_purchase_orders_update BEFORE UPDATE ON public.purchase_orders FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
CREATE TRIGGER handle_company_settings_update BEFORE UPDATE ON public.company_settings FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
CREATE TRIGGER handle_integrations_update BEFORE UPDATE ON public.integrations FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

-------------------------------------------
-- USER & COMPANY CREATION (SUPABASE AUTH HOOK)
-------------------------------------------

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
  company_name_text text;
BEGIN
  -- Extract company name from metadata, fail if empty
  company_name_text := trim(new.raw_user_meta_data->>'company_name');
  IF company_name_text IS NULL OR company_name_text = '' THEN
    RAISE EXCEPTION 'Company name cannot be empty.';
  END IF;

  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (company_name_text)
  RETURNING id INTO new_company_id;

  -- Use the built-in Supabase function to update the user's app_metadata
  -- This is the correct, secure way to associate a user with a company and role
  PERFORM auth.admin_update_user_by_id(
    new.id,
    jsonb_build_object(
      'app_metadata', jsonb_build_object(
        'company_id', new_company_id,
        'role', 'Owner'
      )
    )
  );

  RETURN new;
END;
$$;

-- Create the trigger on the auth.users table
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-------------------------------------------
-- HELPER & UTILITY FUNCTIONS
-------------------------------------------

-- Helper to get the current user's company_id from their JWT
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  select (auth.jwt()->'app_metadata'->>'company_id')::uuid
$$;


-------------------------------------------
-- RLS (ROW-LEVEL SECURITY)
-------------------------------------------

-- Enable RLS on all relevant tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reorder_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_catalogs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can only access data for their own company" ON public.companies FOR SELECT USING (id = auth.company_id());
CREATE POLICY "Users can manage their own company settings" ON public.company_settings FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can manage their own company products" ON public.products FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can manage their own company locations" ON public.locations FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can manage their own company inventory" ON public.inventory FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can manage their own company vendors" ON public.vendors FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can manage their own company sales" ON public.sales FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can manage their own company sale items" ON public.sale_items FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can manage their own company POs" ON public.purchase_orders FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can manage their own company PO items" ON public.purchase_order_items FOR ALL USING (po_id IN (SELECT id FROM public.purchase_orders WHERE company_id = auth.company_id()));
CREATE POLICY "Users can manage their own company customers" ON public.customers FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can manage their own company reorder rules" ON public.reorder_rules FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can manage their own company supplier catalogs" ON public.supplier_catalogs FOR ALL USING (supplier_id IN (SELECT id FROM public.vendors WHERE company_id = auth.company_id()));
CREATE POLICY "Users can manage their own company inventory ledger" ON public.inventory_ledger FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can manage their own company integrations" ON public.integrations FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can see their own audit log" ON public.audit_log FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "Users can manage their own feedback" ON public.user_feedback FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Users can manage their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Users can manage their own messages" ON public.messages FOR ALL USING (conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()));

-- Policy for public assets in Supabase Storage
CREATE POLICY "Enable read access for all users" ON storage.objects FOR SELECT USING (bucket_id = 'public_assets');

-------------------------------------------
-- BUSINESS LOGIC FUNCTIONS (RPC)
-------------------------------------------

-- Completely rewritten to be atomic and safe.
CREATE OR REPLACE FUNCTION public.process_sales_order_inventory(p_sale_id uuid, p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    item_record record;
BEGIN
    FOR item_record IN
        SELECT product_id, location_id, quantity
        FROM public.sale_items
        WHERE sale_id = p_sale_id AND company_id = p_company_id
    LOOP
        UPDATE public.inventory
        SET quantity = quantity - item_record.quantity,
            last_sold_date = CURRENT_DATE
        WHERE product_id = item_record.product_id
          AND location_id = item_record.location_id
          AND company_id = p_company_id;

        INSERT INTO public.inventory_ledger(company_id, product_id, location_id, change_type, quantity_change, new_quantity, related_id, notes, created_by)
        SELECT
            p_company_id,
            item_record.product_id,
            item_record.location_id,
            'sale',
            -item_record.quantity,
            i.quantity,
            p_sale_id,
            (SELECT 'Sale #' || s.sale_number FROM public.sales s WHERE s.id = p_sale_id),
            auth.uid()
        FROM public.inventory i
        WHERE i.product_id = item_record.product_id AND i.location_id = item_record.location_id AND i.company_id = p_company_id;
    END LOOP;
END;
$$;

-- Completely rewritten to be atomic and safe.
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
  new_sale       public.sales;
  new_customer_id uuid;
  total_amount   bigint := 0;
  tax_amount     bigint := 0;
  tax_rate       numeric;
  item_rec       record;
  tmp_sale_items_table text := 'tmp_sale_items_' || replace(gen_random_uuid()::text, '-', '');
BEGIN
    -- 1. Create a temporary table to hold processed sale items
    EXECUTE format($fmt$
        CREATE TEMP TABLE %I (
            product_id   uuid,
            location_id  uuid,
            quantity     integer,
            unit_price   integer,
            cost_at_time integer
        ) ON COMMIT DROP;
    $fmt$, tmp_sale_items_table);

    -- 2. Populate the temp table, joining to get the current cost
    EXECUTE format($fmt$
        INSERT INTO %I (product_id, location_id, quantity, unit_price, cost_at_time)
        SELECT
            (j->>'product_id')::uuid,
            (j->>'location_id')::uuid,
            (j->>'quantity')::integer,
            (j->>'unit_price')::integer,
            inv.cost
        FROM jsonb_array_elements($1) AS j
        JOIN public.inventory inv ON inv.product_id = (j->>'product_id')::uuid AND inv.location_id = (j->>'location_id')::uuid AND inv.company_id = $2;
    $fmt$, tmp_sale_items_table) USING p_sale_items, p_company_id;

    -- 3. Check for sufficient stock for all items
    FOR item_rec IN EXECUTE format('SELECT * FROM %I', tmp_sale_items_table) LOOP
        PERFORM id FROM public.inventory
        WHERE company_id = p_company_id
          AND product_id = item_rec.product_id
          AND location_id = item_rec.location_id
          AND quantity >= item_rec.quantity
        FOR UPDATE; -- Lock the row
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Insufficient stock for product ID % at location ID %', item_rec.product_id, item_rec.location_id;
        END IF;
    END LOOP;

    -- 4. Calculate total amount and tax
    EXECUTE format('SELECT SUM(quantity * unit_price) FROM %I', tmp_sale_items_table) INTO total_amount;
    SELECT cs.tax_rate INTO tax_rate FROM public.company_settings cs WHERE cs.company_id = p_company_id;
    tax_amount := total_amount * COALESCE(tax_rate, 0);

    -- 5. Upsert customer record
    IF p_customer_email IS NOT NULL THEN
        INSERT INTO public.customers(company_id, customer_name, email)
        VALUES (p_company_id, p_customer_name, p_customer_email)
        ON CONFLICT (company_id, email) DO UPDATE SET customer_name = EXCLUDED.customer_name
        RETURNING id INTO new_customer_id;
    END IF;

    -- 6. Insert the main sale record
    INSERT INTO public.sales (company_id, created_by, customer_id, customer_name, customer_email, total_amount, tax_amount, payment_method, notes, external_id)
    VALUES (p_company_id, p_user_id, new_customer_id, p_customer_name, p_customer_email, total_amount, tax_amount, p_payment_method, p_notes, p_external_id)
    RETURNING * INTO new_sale;

    -- 7. Insert sale line items from the temp table
    EXECUTE format($fmt$
        INSERT INTO public.sale_items (sale_id, company_id, product_id, location_id, quantity, unit_price, cost_at_time)
        SELECT $1, $2, product_id, location_id, quantity, unit_price, cost_at_time
        FROM %I;
    $fmt$, tmp_sale_items_table) USING new_sale.id, p_company_id;

    -- 8. Atomically decrement inventory and create ledger entries
    PERFORM public.process_sales_order_inventory(new_sale.id, p_company_id);

    RETURN new_sale;
END;
$$;

SELECT public.refresh_materialized_views();
