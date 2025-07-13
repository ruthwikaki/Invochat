-- Drop existing public tables, functions, and types if they exist to ensure a clean slate.
-- This is designed to be run on a fresh database or to reset the existing one.

-- Drop functions first to remove dependencies
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.update_updated_at_column();
DROP FUNCTION IF EXISTS public.record_sale_transaction_v2(uuid,text,text,text,numeric,text,text,text,jsonb);
DROP FUNCTION IF EXISTS public.record_sale_transaction(uuid,text,text,text,numeric,text,text,text,jsonb);
DROP FUNCTION IF EXISTS public.get_dashboard_metrics(uuid, character varying);

-- Drop views
DROP VIEW IF EXISTS public.inventory_status;
DROP VIEW IF EXISTS public.sales_summary;
DROP VIEW IF EXISTS public.company_dashboard_metrics;

-- Drop tables with dependencies last
DROP TABLE IF EXISTS public.product_variants CASCADE;
DROP TABLE IF EXISTS public.order_line_items CASCADE;
DROP TABLE IF EXISTS public.orders CASCADE;
DROP TABLE IF EXISTS public.refund_line_items CASCADE;
DROP TABLE IF EXISTS public.refunds CASCADE;
DROP TABLE IF EXISTS public.inventory_ledger CASCADE;
DROP TABLE IF EXISTS public.sale_items CASCADE;
DROP TABLE IF EXISTS public.sales CASCADE;
DROP TABLE IF EXISTS public.inventory CASCADE;
DROP TABLE IF EXISTS public.products CASCADE;
DROP TABLE IF EXISTS public.customer_addresses CASCADE;
DROP TABLE IF EXISTS public.customers CASCADE;
DROP TABLE IF EXISTS public.discounts CASCADE;
DROP TABLE IF EXISTS public.suppliers CASCADE;
DROP TABLE IF EXISTS public.sync_logs CASCADE;
DROP TABLE IF EXISTS public.sync_state CASCADE;
DROP TABLE IF EXISTS public.integrations CASCADE;
DROP TABLE IF EXISTS public.channel_fees CASCADE;
DROP TABLE IF EXISTS public.export_jobs CASCADE;
DROP TABLE IF EXISTS public.messages CASCADE;
DROP TABLE IF EXISTS public.conversations CASCADE;
DROP TABLE IF EXISTS public.audit_log CASCADE;
DROP TABLE IF EXISTS public.users CASCADE;
DROP TABLE IF EXISTS public.company_settings CASCADE;
DROP TABLE IF EXISTS public.companies CASCADE;

-- Drop custom types
DROP TYPE IF EXISTS public.user_role;


-- =====================================================
-- SETUP CORE INFRASTRUCTURE
-- =====================================================

-- 1. Companies Table: The root of all data, representing a user's organization.
CREATE TABLE public.companies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.companies IS 'Represents a user''s company or organization.';

-- 2. Custom User Role Type
CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');

-- 3. Users Table: Associates auth users with companies and roles.
CREATE TABLE public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role user_role NOT NULL DEFAULT 'Member',
    created_at timestamp with time zone DEFAULT now()
);
COMMENT ON TABLE public.users IS 'Stores app-specific user information and links to auth schema.';

-- 4. Function to create a new company and user profile on signup.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_company_name text := NEW.raw_user_meta_data->>'company_name';
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (v_company_name)
  RETURNING id INTO v_company_id;

  -- Create a public user profile
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (NEW.id, v_company_id, NEW.email, 'Owner');

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'role', 'Owner')
  WHERE id = NEW.id;
  
  RETURN NEW;
END;
$$;

-- 5. Trigger to execute the user setup function after a new user signs up.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE PROCEDURE public.handle_new_user();

-- =====================================================
-- ESSENTIAL E-COMMERCE TABLES
-- =====================================================

-- 1. Products Table (replaces the old 'inventory' table)
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
    updated_at timestamp with time zone DEFAULT now()
);
COMMENT ON TABLE public.products IS 'Stores parent product information.';
CREATE INDEX idx_products_company_id ON public.products(company_id);
CREATE INDEX idx_products_external_id ON public.products(company_id, external_product_id);


-- 2. Product Variants Table
CREATE TABLE public.product_variants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text,
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
    updated_at timestamp with time zone DEFAULT now()
);
COMMENT ON TABLE public.product_variants IS 'Stores individual SKUs, pricing, and stock for each product variant.';
CREATE INDEX idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX idx_product_variants_sku ON public.product_variants(company_id, sku);
ALTER TABLE public.product_variants ADD CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku);


-- 3. Customers Table
CREATE TABLE public.customers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0, -- in cents
    first_order_date date,
    created_at timestamp with time zone DEFAULT now()
);
CREATE INDEX idx_customers_company_id ON public.customers(company_id);
ALTER TABLE public.customers ADD CONSTRAINT unique_customer_email_per_company UNIQUE (company_id, email);

-- 4. Orders Table
CREATE TABLE public.orders (
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
CREATE INDEX idx_orders_company_id ON public.orders(company_id);
CREATE INDEX idx_orders_customer_id ON public.orders(customer_id);
ALTER TABLE public.orders ADD CONSTRAINT unique_order_number_per_company UNIQUE (company_id, external_order_id, source_platform);

-- 5. Order Line Items Table
CREATE TABLE public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
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
CREATE INDEX idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX idx_order_line_items_variant_id ON public.order_line_items(variant_id);


-- 6. Refunds Table
CREATE TABLE public.refunds (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    refund_number text NOT NULL,
    status text,
    reason text,
    note text,
    total_amount integer NOT NULL, -- in cents
    created_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
    external_refund_id text,
    created_at timestamp with time zone DEFAULT now()
);
CREATE INDEX idx_refunds_order_id ON public.refunds(order_id);

-- 7. Refund Line Items Table
CREATE TABLE public.refund_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    refund_id uuid NOT NULL REFERENCES public.refunds(id) ON DELETE CASCADE,
    order_line_item_id uuid NOT NULL REFERENCES public.order_line_items(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    amount integer NOT NULL, -- in cents
    restock boolean DEFAULT true
);
CREATE INDEX idx_refund_line_items_refund_id ON public.refund_line_items(refund_id);

-- 8. Customer Addresses Table
CREATE TABLE public.customer_addresses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id uuid NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    address_type text DEFAULT 'shipping',
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

-- 9. Discounts Table
CREATE TABLE public.discounts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    code text NOT NULL,
    type text NOT NULL, -- percentage/fixed_amount/free_shipping
    value numeric(10,2) NOT NULL,
    minimum_purchase integer, -- in cents
    usage_limit integer,
    usage_count integer DEFAULT 0,
    applies_to text DEFAULT 'all',
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);
CREATE INDEX idx_discounts_company_id ON public.discounts(company_id, code);

-- =====================================================
-- APP-SPECIFIC & UTILITY TABLES
-- =====================================================

-- 1. Suppliers Table
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

-- 2. Integrations Table
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
CREATE UNIQUE INDEX unique_company_platform ON public.integrations (company_id, platform);

-- 3. Inventory Ledger Table
CREATE TABLE public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid, -- e.g., order_id, refund_id, po_id
    notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
CREATE INDEX idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);

-- 4. Company Settings Table
CREATE TABLE public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone
);

-- 5. Conversations Table
CREATE TABLE public.conversations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    is_starred boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    last_accessed_at timestamp with time zone DEFAULT now()
);
CREATE INDEX idx_conversations_user_id ON public.conversations(user_id);

-- 6. Messages Table
CREATE TABLE public.messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role text NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric(3,2),
    assumptions text[],
    is_error boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now()
);
CREATE INDEX idx_messages_conversation_id ON public.messages(conversation_id);

-- =====================================================
-- TRIGGERS & FUNCTIONS
-- =====================================================

-- 1. Function and Trigger for `updated_at` columns
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
CREATE TRIGGER update_integrations_updated_at BEFORE UPDATE ON public.integrations FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_company_settings_updated_at BEFORE UPDATE ON public.company_settings FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 2. Function to record an order from a platform payload
CREATE OR REPLACE FUNCTION public.record_order_from_platform(p_company_id uuid, p_order_payload jsonb, p_platform text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_id uuid;
    v_customer_id uuid;
    v_variant_id uuid;
    v_line_item jsonb;
BEGIN
    -- 1. Create or update customer
    INSERT INTO public.customers (id, company_id, email, customer_name)
    VALUES (
        COALESCE((p_order_payload->'customer'->>'id'), gen_random_uuid()::text)::uuid,
        p_company_id,
        p_order_payload->'customer'->>'email',
        (p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name')
    )
    ON CONFLICT (company_id, email) DO UPDATE SET
        customer_name = EXCLUDED.customer_name
    RETURNING id INTO v_customer_id;

    -- 2. Insert order
    INSERT INTO public.orders (
        company_id, external_order_id, order_number, customer_id, financial_status, fulfillment_status,
        currency, subtotal, total_tax, total_shipping, total_discounts, total_amount, source_platform, created_at
    )
    VALUES (
        p_company_id,
        p_order_payload->>'id',
        p_order_payload->>'name',
        v_customer_id,
        p_order_payload->>'financial_status',
        p_order_payload->>'fulfillment_status',
        p_order_payload->>'currency',
        (p_order_payload->>'subtotal_price')::numeric * 100,
        (p_order_payload->>'total_tax')::numeric * 100,
        (p_order_payload->>'total_shipping_price')::numeric * 100,
        (p_order_payload->>'total_discounts')::numeric * 100,
        (p_order_payload->>'total_price')::numeric * 100,
        p_platform,
        (p_order_payload->>'created_at')::timestamptz
    )
    ON CONFLICT (company_id, external_order_id, source_platform) DO NOTHING
    RETURNING id INTO v_order_id;

    -- 3. If order already existed, do nothing further.
    IF v_order_id IS NULL THEN
        RETURN;
    END IF;

    -- 4. Insert line items and adjust inventory
    FOR v_line_item IN SELECT * FROM jsonb_array_elements(p_order_payload->'line_items')
    LOOP
        -- Find variant
        SELECT id INTO v_variant_id FROM public.product_variants
        WHERE company_id = p_company_id AND external_variant_id = v_line_item->>'variant_id';

        IF v_variant_id IS NOT NULL THEN
            -- Insert line item
            INSERT INTO public.order_line_items (
                order_id, company_id, variant_id, product_name, variant_title, sku,
                quantity, price, total_discount, tax_amount, external_line_item_id
            )
            VALUES (
                v_order_id,
                p_company_id,
                v_variant_id,
                v_line_item->>'title',
                v_line_item->>'variant_title',
                v_line_item->>'sku',
                (v_line_item->>'quantity')::integer,
                (v_line_item->>'price')::numeric * 100,
                (v_line_item->'discount_allocations'->0->'amount')::numeric * 100,
                (v_line_item->'tax_lines'->0->'price')::numeric * 100,
                v_line_item->>'id'
            );

            -- Adjust inventory and create ledger entry
            PERFORM public.adjust_inventory(
                p_company_id,
                v_variant_id,
                -(v_line_item->>'quantity')::integer,
                'sale',
                v_order_id,
                'Order #' || (p_order_payload->>'name')
            );
        END IF;
    END LOOP;
END;
$$;


-- 3. Function to safely adjust inventory and create a ledger entry
CREATE OR REPLACE FUNCTION public.adjust_inventory(p_company_id uuid, p_variant_id uuid, p_quantity_change integer, p_change_type text, p_related_id uuid, p_notes text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_new_quantity integer;
BEGIN
    UPDATE public.product_variants
    SET inventory_quantity = inventory_quantity + p_quantity_change
    WHERE id = p_variant_id AND company_id = p_company_id
    RETURNING inventory_quantity INTO v_new_quantity;

    INSERT INTO public.inventory_ledger (
        company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes
    )
    VALUES (
        p_company_id, p_variant_id, p_change_type, p_quantity_change, v_new_quantity, p_related_id, p_notes
    );
END;
$$;


-- =====================================================
-- GRANT PERMISSIONS
-- =====================================================
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;

RAISE NOTICE 'InvoChat database schema setup complete.';
