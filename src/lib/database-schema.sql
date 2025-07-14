-- InvoChat Database Schema
-- Version: 1.5
-- Last Updated: 2024-07-28
-- Description: This schema defines the tables, functions, and policies for the InvoChat application.

-- Make sure the `uuid-ossp` extension is enabled.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
-- Enable the `pgcrypto` extension for hashing and encryption functions.
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- =============================================
-- SECTION 1: CORE TABLES
-- =============================================

-- Table to store company information. Each user belongs to a company.
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

-- Table to store company-specific settings for business logic.
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 100000, -- in cents
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;

-- Stores information about suppliers.
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

-- Main product table, representing a unique product.
CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
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
    CONSTRAINT unique_product_source UNIQUE (company_id, external_product_id)
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products (company_id);
-- Add a GIN index for efficient array searching on tags
CREATE INDEX IF NOT EXISTS idx_products_tags_gin ON public.products USING GIN (tags);


-- Product variants, representing specific versions of a product (e.g., size, color).
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
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
    price integer CHECK (price >= 0),
    compare_at_price integer,
    cost integer,
    inventory_quantity integer NOT NULL DEFAULT 0,
    external_variant_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT unique_variant_source UNIQUE (company_id, external_variant_id),
    CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku)
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants (product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants (company_id);

-- Stores customer information.
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text,
    email text,
    first_order_date timestamptz,
    deleted_at timestamptz, -- For soft deletes
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

-- Stores sales order headers.
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
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
    CONSTRAINT unique_order_source UNIQUE (company_id, external_order_id)
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- Stores individual line items for each sales order.
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL CHECK (price >= 0),
    total_discount integer,
    tax_amount integer,
    cost_at_time integer CHECK (cost_at_time >= 0),
    external_line_item_id text
);
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;

-- Stores inventory change history for auditing and tracking.
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger (variant_id);

-- Stores purchase orders made to suppliers.
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status text NOT NULL,
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;

-- Stores individual line items for each purchase order.
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    cost integer NOT NULL
);
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;

-- Stores user feedback on AI suggestions.
CREATE TABLE IF NOT EXISTS public.user_feedback (
  id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  subject_id text NOT NULL, -- The ID of the thing being reviewed (e.g., reorder suggestion ID, anomaly ID)
  subject_type text NOT NULL, -- e.g., 'reorder_suggestion', 'anomaly_explanation'
  feedback text NOT NULL, -- 'helpful' or 'unhelpful'
  created_at timestamptz NOT NULL DEFAULT now(),
  notes text
);
ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;

-- Table to store chat conversations.
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_accessed_at timestamptz NOT NULL DEFAULT now(),
    is_starred boolean NOT NULL DEFAULT false
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

-- Table to store individual chat messages.
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role text NOT NULL,
    content text NOT NULL,
    visualization jsonb,
    component text,
    component_props jsonb,
    confidence real,
    assumptions text[],
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages (conversation_id);

-- Table to manage integrations with external platforms like Shopify.
CREATE TABLE IF NOT EXISTS public.integrations (
  id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  platform text NOT NULL,
  shop_domain text,
  shop_name text,
  is_active boolean NOT NULL DEFAULT false,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  CONSTRAINT unique_integration_per_company UNIQUE (company_id, platform)
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;

-- Table for storing webhook events to prevent replay attacks.
CREATE TABLE IF NOT EXISTS public.webhook_events (
  id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
  webhook_id text NOT NULL,
  processed_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT unique_webhook_per_integration UNIQUE (integration_id, webhook_id)
);
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;


-- =============================================
-- SECTION 2: HELPER FUNCTIONS & TRIGGERS
-- =============================================

-- Function to get the current user's company ID from their JWT claims.
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;

-- Function to handle new user sign-ups.
-- Creates a new company for the user and associates the user with that company.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
  user_company_name text;
BEGIN
  -- Extract company name from the user's metadata, falling back to a default.
  user_company_name := new.raw_user_meta_data ->> 'company_name';
  IF user_company_name IS NULL OR user_company_name = '' THEN
    user_company_name := new.email || '''s Company';
  END IF;

  -- Create a new company for the new user.
  INSERT INTO public.companies (name)
  VALUES (user_company_name)
  RETURNING id INTO new_company_id;

  -- Update the user's app_metadata with the new company_id and role.
  new.raw_app_meta_data := new.raw_app_meta_data || jsonb_build_object(
    'company_id', new_company_id,
    'role', 'Owner'
  );
  
  -- Create default settings for the new company.
  INSERT INTO public.company_settings (company_id) VALUES (new_company_id);

  RETURN new;
END;
$$;

-- Trigger to execute the handle_new_user function when a new user is created.
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Trigger to automatically update the `updated_at` timestamp on tables.
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Apply the updated_at trigger to relevant tables.
CREATE OR REPLACE TRIGGER handle_updated_at
BEFORE UPDATE ON public.companies
FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

CREATE OR REPLACE TRIGGER handle_updated_at
BEFORE UPDATE ON public.company_settings
FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

-- =============================================
-- SECTION 3: ROW-LEVEL SECURITY (RLS) POLICIES
-- =============================================

-- Generic policy to allow full access based on the user's company_id.
CREATE OR REPLACE FUNCTION public.create_company_rls_policy(table_name text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  EXECUTE format('DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.%I;', table_name);
  EXECUTE format('
    CREATE POLICY "Allow full access based on company_id"
    ON public.%I
    FOR ALL
    USING (company_id = get_current_company_id())
    WITH CHECK (company_id = get_current_company_id());
  ', table_name);
END;
$$;

-- Apply the generic RLS policy to all tables with a `company_id` column.
SELECT public.create_company_rls_policy(table_name::text)
FROM information_schema.tables
WHERE table_schema = 'public' AND table_name IN (
    'companies', 'company_settings', 'suppliers', 'products', 'product_variants', 
    'customers', 'orders', 'order_line_items', 'inventory_ledger', 
    'purchase_orders', 'purchase_order_line_items', 'user_feedback',
    'conversations', 'messages', 'integrations', 'webhook_events'
);

-- Policy to allow a user to see only their own conversations.
DROP POLICY IF EXISTS "Allow individual access to own conversations" ON public.conversations;
CREATE POLICY "Allow individual access to own conversations"
ON public.conversations
FOR SELECT
USING (auth.uid() = user_id);

-- Policy to allow a user to see messages in conversations they are part of.
DROP POLICY IF EXISTS "Allow individual access to own messages" ON public.messages;
CREATE POLICY "Allow individual access to own messages"
ON public.messages
FOR SELECT
USING (
  company_id = get_current_company_id() AND
  conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid())
);


-- =============================================
-- SECTION 4: DATABASE VIEWS FOR SIMPLIFIED QUERIES
-- =============================================

-- A view to easily get product variants with their parent product details.
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    NULL::uuid as location_id, -- Placeholder for multi-location, currently unused
    'Default Warehouse' as location_name -- Placeholder
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;

-- =============================================
-- SECTION 5: RPC FUNCTIONS FOR BUSINESS LOGIC
-- =============================================

-- Function to get all users associated with a company.
CREATE OR REPLACE FUNCTION public.get_users_for_company(p_company_id uuid)
RETURNS TABLE (id uuid, email text, role text)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT u.id, u.email, u.raw_app_meta_data->>'role' as role
    FROM auth.users u
    WHERE u.raw_app_meta_data->>'company_id' = p_company_id::text;
END;
$$;


-- A more robust RPC function to record an order from a platform payload.
-- This function is transactional and ensures data integrity.
CREATE OR REPLACE FUNCTION public.record_order_from_platform(
    p_company_id uuid,
    p_order_payload jsonb,
    p_platform text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_customer_id uuid;
    v_order_id uuid;
    v_variant_id uuid;
    v_line_item jsonb;
    v_sku text;
    v_quantity integer;
    v_new_inventory_quantity integer;
BEGIN
    -- Step 1: Find or create the customer record.
    SELECT id INTO v_customer_id
    FROM public.customers
    WHERE company_id = p_company_id AND email = (p_order_payload->'customer'->>'email');

    IF v_customer_id IS NULL THEN
        INSERT INTO public.customers (company_id, customer_name, email)
        VALUES (
            p_company_id,
            p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name',
            p_order_payload->'customer'->>'email'
        )
        RETURNING id INTO v_customer_id;
    END IF;

    -- Step 2: Insert or update the order header.
    INSERT INTO public.orders (
        company_id, external_order_id, customer_id, financial_status, fulfillment_status,
        currency, subtotal, total_tax, total_shipping, total_discounts, total_amount, source_platform, created_at
    )
    VALUES (
        p_company_id,
        p_order_payload->>'id',
        v_customer_id,
        p_order_payload->>'financial_status',
        p_order_payload->>'fulfillment_status',
        p_order_payload->>'currency',
        (p_order_payload->>'subtotal_price')::numeric * 100,
        (p_order_payload->>'total_tax')::numeric * 100,
        (p_order_payload->>'total_shipping_price_set'->'shop_money'->>'amount')::numeric * 100,
        (p_order_payload->>'total_discounts')::numeric * 100,
        (p_order_payload->>'total_price')::numeric * 100,
        p_platform,
        (p_order_payload->>'created_at')::timestamptz
    )
    ON CONFLICT (company_id, external_order_id) DO UPDATE SET
        financial_status = EXCLUDED.financial_status,
        fulfillment_status = EXCLUDED.fulfillment_status,
        total_amount = EXCLUDED.total_amount,
        updated_at = now()
    RETURNING id INTO v_order_id;
    
    -- Step 3: Loop through line items, update inventory, and insert line item records.
    FOR v_line_item IN SELECT * FROM jsonb_array_elements(p_order_payload->'line_items')
    LOOP
        v_sku := v_line_item->>'sku';
        v_quantity := (v_line_item->>'quantity')::integer;

        -- Find the corresponding product variant.
        SELECT id INTO v_variant_id
        FROM public.product_variants
        WHERE company_id = p_company_id AND sku = v_sku;

        -- If a variant is found, update its inventory.
        IF v_variant_id IS NOT NULL THEN
            UPDATE public.product_variants
            SET inventory_quantity = inventory_quantity - v_quantity
            WHERE id = v_variant_id
            RETURNING inventory_quantity INTO v_new_inventory_quantity;

            -- Create a ledger entry for the sale.
            INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
            VALUES (p_company_id, v_variant_id, 'sale', -v_quantity, v_new_inventory_quantity, v_order_id, 'Order #' || (p_order_payload->>'name'));
        END IF;

        -- Insert the order line item.
        INSERT INTO public.order_line_items (
            order_id, variant_id, company_id, product_name, variant_title, sku, quantity, price, external_line_item_id
        )
        VALUES (
            v_order_id,
            v_variant_id,
            p_company_id,
            v_line_item->>'name',
            v_line_item->>'variant_title',
            v_sku,
            v_quantity,
            (v_line_item->>'price')::numeric * 100,
            v_line_item->>'id'
        );
    END LOOP;
END;
$$;

-- Function to create purchase orders from a list of reorder suggestions.
CREATE OR REPLACE FUNCTION public.create_purchase_orders_from_suggestions(
    p_company_id uuid,
    p_user_id uuid,
    p_suggestions jsonb
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    suggestion jsonb;
    supplier_map jsonb := '{}'::jsonb;
    po_map jsonb := '{}'::jsonb;
    v_supplier_id uuid;
    v_po_id uuid;
    v_po_number text;
    v_item_cost integer;
    v_total_cost integer;
    created_po_count integer := 0;
BEGIN
    -- Group suggestions by supplier_id
    FOR suggestion IN SELECT * FROM jsonb_array_elements(p_suggestions)
    LOOP
        v_supplier_id := (suggestion->>'supplier_id')::uuid;
        IF v_supplier_id IS NOT NULL THEN
            IF supplier_map->v_supplier_id::text IS NULL THEN
                supplier_map := jsonb_set(supplier_map, ARRAY[v_supplier_id::text], '[]'::jsonb);
            END IF;
            supplier_map := jsonb_set(supplier_map, ARRAY[v_supplier_id::text], (supplier_map->v_supplier_id::text) || suggestion);
        END IF;
    END LOOP;

    -- Create a PO for each supplier
    FOR v_supplier_id IN SELECT (jsonb_object_keys(supplier_map))::uuid
    LOOP
        v_po_number := 'PO-' || to_char(now(), 'YYYYMMDD') || '-' || (created_po_count + 1);
        
        INSERT INTO public.purchase_orders (company_id, supplier_id, status, po_number, total_cost)
        VALUES (p_company_id, v_supplier_id, 'Draft', v_po_number, 0)
        RETURNING id INTO v_po_id;

        v_total_cost := 0;

        FOR suggestion IN SELECT * FROM jsonb_array_elements(supplier_map->v_supplier_id::text)
        LOOP
            v_item_cost := (suggestion->>'unit_cost')::integer;
            
            INSERT INTO public.purchase_order_line_items (purchase_order_id, variant_id, quantity, cost)
            VALUES (v_po_id, (suggestion->>'variant_id')::uuid, (suggestion->>'suggested_reorder_quantity')::integer, v_item_cost);
            
            v_total_cost := v_total_cost + ((suggestion->>'suggested_reorder_quantity')::integer * v_item_cost);
        END LOOP;

        UPDATE public.purchase_orders SET total_cost = v_total_cost WHERE id = v_po_id;

        -- Create an audit log entry for the PO creation
        INSERT INTO public.audit_log (company_id, user_id, action, details)
        VALUES (p_company_id, p_user_id, 'purchase_order_created', jsonb_build_object(
            'po_id', v_po_id,
            'po_number', v_po_number,
            'supplier_id', v_supplier_id,
            'total_cost', v_total_cost,
            'item_count', jsonb_array_length(supplier_map->v_supplier_id::text)
        ));

        created_po_count := created_po_count + 1;
    END LOOP;

    RETURN created_po_count;
END;
$$;


-- Final check on RLS for the audit_log table.
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow admins to read audit logs" ON public.audit_log;
CREATE POLICY "Allow admins to read audit logs"
ON public.audit_log
FOR SELECT
USING (company_id = get_current_company_id());


-- That's a wrap for version 1.5!
-- END OF SCHEMA FILE

