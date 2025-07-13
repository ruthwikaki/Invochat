
-- ===================================================================
--  DATABASE SETUP SCRIPT FOR InvoChat
-- ===================================================================
--  This script is idempotent and can be run multiple times safely.
--  It creates tables, functions, and sets up row-level security.
-- ===================================================================


-- ===================================================================
--  1. HELPER FUNCTIONS & EXTENSIONS
-- ===================================================================
-- Enable the UUID extension if it's not already enabled.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";


-- ===================================================================
--  2. TABLE CREATION
-- ===================================================================

-- Stores company-specific information.
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Stores user information, linking them to a company and role.
CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role text NOT NULL CHECK (role IN ('Owner', 'Admin', 'Member')) DEFAULT 'Member',
    created_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone
);

-- Stores supplier/vendor information.
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    notes text,
    default_lead_time_days integer,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Stores parent product information.
CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- Stores individual product variants (SKUs).
CREATE TABLE IF NOT EXISTS public.product_variants (
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
    price integer, -- in cents
    compare_at_price integer, -- in cents
    cost integer, -- in cents
    inventory_quantity integer NOT NULL DEFAULT 0,
    external_variant_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    reorder_point integer,
    reorder_quantity integer,
    lead_time_days integer,
    last_sold_date date,
    version integer NOT NULL DEFAULT 1,
    deleted_at timestamp with time zone
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;

-- Stores customer information.
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0, -- in cents
    first_order_date date,
    created_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

-- Stores customer addresses.
CREATE TABLE IF NOT EXISTS public.customer_addresses (
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

-- Stores order headers.
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer NOT NULL, -- in cents
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- Stores order line items.
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL, -- in cents
    total_discount integer,
    tax_amount integer,
    cost_at_time integer, -- in cents
    external_line_item_id text
);
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;


-- Stores refund headers.
CREATE TABLE IF NOT EXISTS public.refunds (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    refund_number text NOT NULL,
    status text,
    reason text,
    note text,
    total_amount integer NOT NULL, -- in cents
    external_refund_id text,
    created_at timestamp with time zone DEFAULT now()
);
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;

-- Stores refund line items.
CREATE TABLE IF NOT EXISTS public.refund_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    refund_id uuid NOT NULL REFERENCES public.refunds(id) ON DELETE CASCADE,
    order_line_item_id uuid NOT NULL REFERENCES public.order_line_items(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    amount integer NOT NULL, -- in cents
    restock boolean DEFAULT false
);
ALTER TABLE public.refund_line_items ENABLE ROW LEVEL SECURITY;

-- Stores discount information.
CREATE TABLE IF NOT EXISTS public.discounts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    code text NOT NULL,
    type text NOT NULL,
    value numeric NOT NULL,
    minimum_purchase integer, -- in cents
    usage_limit integer,
    usage_count integer,
    applies_to text,
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    is_active boolean
);
ALTER TABLE public.discounts ENABLE ROW LEVEL SECURITY;

-- Audit trail for inventory adjustments.
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;


-- ===================================================================
--  3. TRIGGER FOR NEW USER/COMPANY CREATION
-- ===================================================================
-- This function is triggered when a new user signs up.
-- It creates a new company, a corresponding public.users entry,
-- and sets the company_id and role in the auth.users metadata.

-- Drop the old function and trigger if they exist to avoid conflicts.
-- The CASCADE option is crucial to drop the dependent trigger automatically.
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  new_company_id uuid;
  user_email text;
  user_company_name text;
BEGIN
  -- Create a new company
  user_company_name := COALESCE(NEW.raw_app_meta_data->>'company_name', 'My Company');
  INSERT INTO public.companies (name) VALUES (user_company_name) RETURNING id INTO new_company_id;

  -- Create a new user entry in public.users
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (NEW.id, new_company_id, NEW.email, 'Owner');
  
  -- Update the user's app_metadata in auth.users
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  WHERE id = NEW.id;
  
  RETURN NEW;
END;
$$;

-- Create the trigger on the auth.users table
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- ===================================================================
--  4. ROW-LEVEL SECURITY (RLS)
-- ===================================================================
-- This section ensures users can only access data from their own company.

-- Helper function to get the company_id from a user's JWT.
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT (auth.jwt()->'app_metadata'->>'company_id')::uuid
$$;


-- Generic RLS policy for tables with a company_id column.
CREATE OR REPLACE FUNCTION public.create_rls_policy(table_name text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', table_name);
  EXECUTE format('DROP POLICY IF EXISTS "Users can only see their own company''s data." ON public.%I;', table_name);
  EXECUTE format(
    'CREATE POLICY "Users can only see their own company''s data." ON public.%I FOR ALL USING (company_id = public.get_current_company_id());',
    table_name
  );
END;
$$;

-- Apply the RLS policy to all relevant tables.
SELECT public.create_rls_policy('products');
SELECT public.create_rls_policy('product_variants');
SELECT public.create_rls_policy('suppliers');
SELECT public.create_rls_policy('customers');
SELECT public.create_rls_policy('orders');
SELECT public.create_rls_policy('order_line_items');
SELECT public.create_rls_policy('refunds');
SELECT public.create_rls_policy('refund_line_items');
SELECT public.create_rls_policy('discounts');
SELECT public.create_rls_policy('inventory_ledger');


-- ===================================================================
--  5. INDEXES FOR PERFORMANCE
-- ===================================================================
-- Indexes are crucial for fast query performance, especially on large tables.

-- Products & Variants
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_variants_sku_company ON public.product_variants(sku, company_id);

-- Orders & Customers
CREATE INDEX IF NOT EXISTS idx_orders_company_date ON public.orders(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_customers_company_email ON public.customers(company_id, email);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant ON public.order_line_items(variant_id);

-- Other
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant ON public.inventory_ledger(variant_id, created_at DESC);


-- ===================================================================
--  6. Grant USAGE on public schema to authenticated role
-- ===================================================================
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- ===================================================================
--  7. RPC function for recording an order transactionally
-- ===================================================================

CREATE OR REPLACE FUNCTION public.record_order_from_platform(
    p_company_id uuid,
    p_platform text,
    p_order_payload jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_customer_id uuid;
    v_order_id uuid;
    v_variant_id uuid;
    v_item jsonb;
BEGIN
    -- Step 1: Find or create the customer record
    INSERT INTO public.customers (company_id, email, customer_name)
    VALUES (
        p_company_id,
        p_order_payload->'customer'->>'email',
        COALESCE(p_order_payload->'customer'->>'first_name', '') || ' ' || COALESCE(p_order_payload->'customer'->>'last_name', '')
    )
    ON CONFLICT (company_id, email) DO UPDATE SET
        customer_name = EXCLUDED.customer_name
    RETURNING id INTO v_customer_id;

    -- Step 2: Create the main order record
    INSERT INTO public.orders (
        company_id,
        external_order_id,
        order_number,
        customer_id,
        financial_status,
        fulfillment_status,
        currency,
        subtotal,
        total_tax,
        total_shipping,
        total_discounts,
        total_amount,
        source_platform,
        created_at
    )
    VALUES (
        p_company_id,
        p_order_payload->>'id',
        p_order_payload->>'name',
        v_customer_id,
        p_order_payload->>'financial_status',
        p_order_payload->>'fulfillment_status',
        p_order_payload->>'currency',
        ( (p_order_payload->>'subtotal_price')::numeric * 100 )::integer,
        ( (p_order_payload->>'total_tax')::numeric * 100 )::integer,
        ( (p_order_payload->>'total_shipping_price_set'->'shop_money'->>'amount')::numeric * 100 )::integer,
        ( (p_order_payload->>'total_discounts')::numeric * 100 )::integer,
        ( (p_order_payload->>'total_price')::numeric * 100 )::integer,
        p_platform,
        (p_order_payload->>'created_at')::timestamptz
    )
    ON CONFLICT (company_id, external_order_id) DO UPDATE SET
        financial_status = EXCLUDED.financial_status,
        fulfillment_status = EXCLUDED.fulfillment_status,
        updated_at = now()
    RETURNING id INTO v_order_id;
    
    -- If no order was created or found, exit
    IF v_order_id IS NULL THEN
        SELECT id INTO v_order_id FROM public.orders WHERE company_id = p_company_id AND external_order_id = (p_order_payload->>'id');
        IF v_order_id IS NULL THEN
            RAISE NOTICE 'Could not create or find order for external_id %', p_order_payload->>'id';
            RETURN;
        END IF;
    END IF;

    -- Step 3: Loop through line items to create them and adjust inventory
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_order_payload->'line_items')
    LOOP
        -- Find the corresponding variant in our system
        SELECT id INTO v_variant_id FROM public.product_variants
        WHERE company_id = p_company_id AND external_variant_id = (v_item->>'variant_id');

        IF v_variant_id IS NOT NULL THEN
            -- Insert the line item
            INSERT INTO public.order_line_items (
                order_id,
                variant_id,
                company_id,
                product_name,
                variant_title,
                sku,
                quantity,
                price,
                external_line_item_id
            )
            VALUES (
                v_order_id,
                v_variant_id,
                p_company_id,
                v_item->>'title',
                v_item->>'variant_title',
                v_item->>'sku',
                (v_item->>'quantity')::integer,
                ( (v_item->>'price')::numeric * 100 )::integer,
                v_item->>'id'
            ) ON CONFLICT DO NOTHING;

            -- Adjust inventory and create ledger entry
            PERFORM public.adjust_inventory(
                p_company_id,
                v_variant_id,
                -(v_item->>'quantity')::integer,
                'sale',
                v_order_id
            );
        ELSE
            RAISE NOTICE 'Skipping line item with unknown variant_id %', v_item->>'variant_id';
        END IF;
    END LOOP;

END;
$$;


CREATE OR REPLACE FUNCTION public.adjust_inventory(
    p_company_id uuid,
    p_variant_id uuid,
    p_quantity_change integer,
    p_change_type text,
    p_related_id uuid DEFAULT NULL,
    p_notes text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_current_quantity integer;
    v_new_quantity integer;
BEGIN
    -- Lock the row to prevent race conditions
    SELECT inventory_quantity INTO v_current_quantity
    FROM public.product_variants
    WHERE id = p_variant_id AND company_id = p_company_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Variant with ID % not found for company %', p_variant_id, p_company_id;
    END IF;

    v_new_quantity := v_current_quantity + p_quantity_change;

    -- Update the inventory quantity
    UPDATE public.product_variants
    SET inventory_quantity = v_new_quantity,
        updated_at = now()
    WHERE id = p_variant_id;

    -- Create a ledger entry for the adjustment
    INSERT INTO public.inventory_ledger (
        company_id,
        variant_id,
        change_type,
        quantity_change,
        new_quantity,
        related_id,
        notes
    ) VALUES (
        p_company_id,
        p_variant_id,
        p_change_type,
        p_quantity_change,
        v_new_quantity,
        p_related_id,
        p_notes
    );

    RETURN v_new_quantity;
END;
$$;
