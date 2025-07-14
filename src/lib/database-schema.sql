-- InvoChat - Conversational Inventory Intelligence
-- © 2024 Firebase
-- https://firebase.google.com

-- =============================================
-- 1. EXTENSIONS & BASIC SETUP
-- =============================================
-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- Enable vector support for pgvector
CREATE EXTENSION IF NOT EXISTS "vector";
-- Enable pg_cron for scheduled tasks
CREATE EXTENSION IF NOT EXISTS "pg_cron";
-- Enable pgroonga for full-text search (if available)
-- CREATE EXTENSION IF NOT EXISTS "pgroonga";

-- =============================================
-- 2. ENUMS AND CUSTOM TYPES
-- =============================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'integration_platform') THEN
        CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'inventory_change_type') THEN
        CREATE TYPE public.inventory_change_type AS ENUM ('sale', 'purchase_order', 'return', 'manual_adjustment', 'initial_stock', 'reconciliation', 'transfer_in', 'transfer_out');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'alert_severity') THEN
       CREATE TYPE public.alert_severity AS ENUM ('info', 'warning', 'critical');
    END IF;
     IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'po_status') THEN
        CREATE TYPE public.po_status AS ENUM ('draft', 'sent', 'partially_received', 'received', 'cancelled');
    END IF;
END$$;


-- =============================================
-- 3. CORE TABLES
-- =============================================

-- Stores company-level information
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

-- Stores user information, linking them to companies
CREATE TABLE IF NOT EXISTS public.users (
    id uuid NOT NULL PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role user_role NOT NULL DEFAULT 'Member',
    full_name text,
    avatar_url text
);
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Stores company-specific business logic settings
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 100000,
    currency text NOT NULL DEFAULT 'USD',
    timezone text NOT NULL DEFAULT 'UTC',
    tax_rate numeric(5,4) DEFAULT 0.00,
    custom_rules jsonb,
    subscription_plan text,
    subscription_status text,
    subscription_expires_at timestamp with time zone,
    stripe_customer_id text,
    stripe_subscription_id text,
    promo_sales_lift_multiplier numeric(4,2) NOT NULL DEFAULT 2.50,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;

-- Stores supplier information
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

-- Stores product information (the parent entity for variants)
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
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    UNIQUE (company_id, external_product_id)
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- Stores product variants (SKUs)
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
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
    price integer CHECK (price IS NULL OR price >= 0),
    compare_at_price integer CHECK (compare_at_price IS NULL OR compare_at_price >= 0),
    cost integer CHECK (cost IS NULL OR cost >= 0),
    inventory_quantity integer NOT NULL DEFAULT 0 CHECK (inventory_quantity >= 0),
    external_variant_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    UNIQUE (company_id, sku),
    UNIQUE (company_id, external_variant_id)
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;

-- Stores customer information
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text,
    email text,
    total_orders integer DEFAULT 0 NOT NULL,
    total_spent integer DEFAULT 0 NOT NULL,
    first_order_date date,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    UNIQUE (company_id, email)
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

-- Stores sales orders
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id),
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer NOT NULL CHECK (subtotal >= 0),
    total_tax integer CHECK (total_tax IS NULL OR total_tax >= 0),
    total_shipping integer CHECK (total_shipping IS NULL OR total_shipping >= 0),
    total_discounts integer CHECK (total_discounts IS NULL OR total_discounts >= 0),
    total_amount integer NOT NULL CHECK (total_amount >= 0),
    source_platform text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- Stores line items for each sales order
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL CHECK (quantity > 0),
    price integer NOT NULL CHECK (price >= 0),
    total_discount integer CHECK (total_discount IS NULL OR total_discount >= 0),
    tax_amount integer CHECK (tax_amount IS NULL OR tax_amount >= 0),
    cost_at_time integer CHECK (cost_at_time IS NULL OR cost_at_time >= 0),
    external_line_item_id text
);
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;


-- Stores purchase orders
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id),
    status po_status NOT NULL DEFAULT 'draft',
    po_number text NOT NULL,
    total_cost integer NOT NULL CHECK (total_cost >= 0),
    expected_arrival_date date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid REFERENCES public.users(id),
    updated_at timestamp with time zone
);
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;


-- Stores line items for each purchase order
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity integer NOT NULL CHECK (quantity > 0),
    cost integer NOT NULL CHECK (cost >= 0)
);
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;


-- Stores inventory change history (ledger)
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type inventory_change_type NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;


-- Stores conversations for the chat interface
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_accessed_at timestamp with time zone DEFAULT now() NOT NULL,
    is_starred boolean DEFAULT false NOT NULL
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

-- Stores messages for each conversation
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role text NOT NULL,
    content text NOT NULL,
    visualization jsonb,
    component text,
    component_props jsonb,
    confidence real,
    assumptions text[],
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;


-- Stores user feedback on AI responses
CREATE TABLE IF NOT EXISTS public.user_feedback (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;

-- Stores integrations with external platforms
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform integration_platform NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT true NOT NULL,
    last_sync_at timestamp with time zone,
    sync_status text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    UNIQUE(company_id, platform)
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    processed_at timestamp with time zone DEFAULT now() NOT NULL,
    UNIQUE(integration_id, webhook_id)
);
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;


CREATE TABLE IF NOT EXISTS public.audit_log (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;


CREATE TABLE IF NOT EXISTS public.import_jobs (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES public.users(id),
    import_type text NOT NULL,
    file_name text NOT NULL,
    status text NOT NULL,
    total_rows integer,
    processed_rows integer,
    failed_rows integer,
    errors jsonb,
    summary jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone
);
ALTER TABLE public.import_jobs ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES public.users(id),
    status text NOT NULL DEFAULT 'pending',
    file_url text,
    expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone
);
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;


-- =============================================
-- 4. VIEWS & MATERIALIZED VIEWS
-- =============================================

-- View to combine product and variant details for easier querying
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    v.id,
    v.product_id,
    v.company_id,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type,
    v.title,
    v.sku,
    v.price,
    v.cost,
    v.inventory_quantity,
    null::uuid as location_id,
    'Default Warehouse' as location_name
FROM public.product_variants v
JOIN public.products p ON v.product_id = p.id;


-- =============================================
-- 5. ROW LEVEL SECURITY (RLS) POLICIES
-- =============================================

-- Function to get the company_id of the currently authenticated user
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::json->>'company_id', '')::uuid;
$$;


-- Grant usage on the function to authenticated users
GRANT EXECUTE ON FUNCTION public.get_current_company_id() TO authenticated;


-- Generic RLS policies for tables with a company_id
DO $$
DECLARE
    t_name TEXT;
BEGIN
    FOR t_name IN
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name IN (
            'companies', 'users', 'company_settings', 'suppliers', 'products',
            'product_variants', 'customers', 'orders', 'order_line_items', 'inventory_ledger',
            'conversations', 'messages', 'integrations', 'user_feedback',
            'audit_log', 'import_jobs', 'export_jobs', 'purchase_orders', 'purchase_order_line_items'
        )
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t_name);
        EXECUTE format('DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.%I;', t_name);
        EXECUTE format(
            'CREATE POLICY "Allow full access based on company_id" ON public.%I FOR ALL ' ||
            'USING (company_id = get_current_company_id()) ' ||
            'WITH CHECK (company_id = get_current_company_id());',
            t_name
        );
    END LOOP;
END;
$$;


-- Special policy for users table to allow users to see their own record
DROP POLICY IF EXISTS "Allow user to see their own record" ON public.users;
CREATE POLICY "Allow user to see their own record" ON public.users FOR SELECT
USING (id = auth.uid());


-- =============================================
-- 6. FUNCTIONS AND TRIGGERS
-- =============================================

-- Trigger function to create a company and user record on new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_company_id uuid;
    v_company_name text;
    v_user_role user_role;
BEGIN
    -- Extract company name from metadata, default if not present
    v_company_name := new.raw_user_meta_data->>'company_name';
    IF v_company_name IS NULL OR v_company_name = '' THEN
        v_company_name := new.email || '''s Company';
    END IF;
    
    -- Insert a new company
    INSERT INTO public.companies (name)
    VALUES (v_company_name)
    RETURNING id INTO v_company_id;

    -- The first user to sign up is the Owner
    v_user_role := 'Owner';

    -- Insert a new user record linked to the new company
    INSERT INTO public.users (id, company_id, role, full_name, avatar_url)
    VALUES (
        new.id,
        v_company_id,
        v_user_role,
        new.raw_user_meta_data->>'full_name',
        new.raw_user_meta_data->>'avatar_url'
    );
    
    -- Update the user's app_metadata with the company_id and role
    UPDATE auth.users
    SET app_metadata = app_metadata || jsonb_build_object('company_id', v_company_id, 'role', v_user_role)
    WHERE id = new.id;
    
    RETURN new;
END;
$$;

-- Attach the trigger to the auth.users table
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();


-- Trigger to log inventory changes automatically
CREATE OR REPLACE FUNCTION public.log_inventory_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO public.inventory_ledger (company_id, variant_id, quantity_change, new_quantity, change_type, notes)
    VALUES (
        NEW.company_id,
        NEW.id,
        NEW.inventory_quantity - OLD.inventory_quantity,
        NEW.inventory_quantity,
        'manual_adjustment',
        'Manual stock adjustment'
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_inventory_update ON public.product_variants;
CREATE TRIGGER on_inventory_update
AFTER UPDATE OF inventory_quantity ON public.product_variants
FOR EACH ROW
WHEN (OLD.inventory_quantity IS DISTINCT FROM NEW.inventory_quantity)
EXECUTE FUNCTION public.log_inventory_change();



-- =============================================
-- 7. RPC FUNCTIONS
-- =============================================

-- Function to get all users for a given company (for team management)
CREATE OR REPLACE FUNCTION public.get_users_for_company(p_company_id uuid)
RETURNS TABLE (id uuid, email text, role user_role)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT u.id, a.email, u.role
    FROM public.users u
    JOIN auth.users a ON u.id = a.id
    WHERE u.company_id = p_company_id;
END;
$$;

-- Function to remove a user from a company
CREATE OR REPLACE FUNCTION public.remove_user_from_company(p_user_id uuid, p_company_id uuid, p_performing_user_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_performing_user_role user_role;
BEGIN
    -- Check if the performing user is an Admin or Owner
    SELECT role INTO v_performing_user_role
    FROM public.users
    WHERE id = p_performing_user_id AND company_id = p_company_id;

    IF v_performing_user_role NOT IN ('Admin', 'Owner') THEN
        RAISE EXCEPTION 'You do not have permission to remove users.';
    END IF;

    -- Prevent removing the last owner
    IF (SELECT count(*) FROM public.users WHERE company_id = p_company_id AND role = 'Owner') = 1
       AND (SELECT role FROM public.users WHERE id = p_user_id) = 'Owner' THEN
        RAISE EXCEPTION 'Cannot remove the last owner of the company.';
    END IF;
    
    DELETE FROM public.users WHERE id = p_user_id AND company_id = p_company_id;
END;
$$;


-- Function to update a user's role in a company
CREATE OR REPLACE FUNCTION public.update_user_role_in_company(p_user_id uuid, p_company_id uuid, p_new_role user_role)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.users
    SET role = p_new_role
    WHERE id = p_user_id AND company_id = p_company_id;

    UPDATE auth.users
    SET app_metadata = app_metadata || jsonb_build_object('role', p_new_role)
    WHERE id = p_user_id;
END;
$$;


-- Function to handle an order from an external platform
CREATE OR REPLACE FUNCTION public.record_order_from_platform(p_company_id uuid, p_order_payload jsonb, p_platform text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_customer_id uuid;
    v_order_id uuid;
    v_variant_id uuid;
    line_item jsonb;
    v_sku text;
BEGIN
    -- Find or create customer
    INSERT INTO public.customers (company_id, customer_name, email)
    VALUES (p_company_id, p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name', p_order_payload->'customer'->>'email')
    ON CONFLICT (company_id, email) DO UPDATE SET customer_name = EXCLUDED.customer_name
    RETURNING id INTO v_customer_id;

    -- Record the order
    INSERT INTO public.orders (company_id, customer_id, order_number, total_amount, subtotal, currency, source_platform, external_order_id, created_at)
    VALUES (
        p_company_id,
        v_customer_id,
        p_order_payload->>'id',
        (p_order_payload->>'total_price')::numeric * 100,
        (p_order_payload->>'subtotal_price')::numeric * 100,
        p_order_payload->>'currency',
        p_platform,
        p_order_payload->>'id',
        (p_order_payload->>'created_at')::timestamptz
    )
    RETURNING id INTO v_order_id;
    
    -- Process line items
    FOR line_item IN SELECT * FROM jsonb_array_elements(p_order_payload->'line_items')
    LOOP
        v_sku := line_item->>'sku';
        
        -- Find variant ID based on SKU
        SELECT id INTO v_variant_id FROM public.product_variants WHERE company_id = p_company_id AND sku = v_sku;

        INSERT INTO public.order_line_items (order_id, company_id, variant_id, sku, product_name, quantity, price)
        VALUES (
            v_order_id,
            p_company_id,
            v_variant_id,
            v_sku,
            line_item->>'name',
            (line_item->>'quantity')::integer,
            (line_item->>'price')::numeric * 100
        );
        
        -- Decrement inventory (if variant is tracked)
        IF v_variant_id IS NOT NULL THEN
            UPDATE public.product_variants
            SET inventory_quantity = inventory_quantity - (line_item->>'quantity')::integer
            WHERE id = v_variant_id AND company_id = p_company_id;
        END IF;
    END LOOP;
END;
$$;


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
    supplier_name text;
    v_supplier_id uuid;
    v_po_id uuid;
    v_po_number text;
    v_total_cost integer;
    created_po_count integer := 0;
BEGIN
    -- Group suggestions by supplier
    FOR suggestion IN SELECT * FROM jsonb_array_elements(p_suggestions)
    LOOP
        supplier_name := COALESCE(suggestion->>'supplier_name', 'Unassigned');
        IF NOT supplier_map ? supplier_name THEN
            supplier_map := jsonb_set(supplier_map, ARRAY[supplier_name], '[]'::jsonb);
        END IF;
        supplier_map := jsonb_set(supplier_map, ARRAY[supplier_name], (supplier_map->supplier_name) || suggestion);
    END LOOP;

    -- Create one PO per supplier
    FOR supplier_name, suggestion IN SELECT * FROM jsonb_each(supplier_map)
    LOOP
        -- Find supplier ID
        SELECT id INTO v_supplier_id FROM public.suppliers WHERE name = supplier_name AND company_id = p_company_id;
        
        v_total_cost := (SELECT sum(((item->>'suggested_reorder_quantity')::integer * (item->>'unit_cost')::integer)) FROM jsonb_array_elements(suggestion) as item);
        v_po_number := 'PO-' || to_char(now(), 'YYYYMMDD') || '-' || (created_po_count + 1);

        INSERT INTO public.purchase_orders (company_id, supplier_id, status, po_number, total_cost, created_by)
        VALUES (p_company_id, v_supplier_id, 'draft', v_po_number, v_total_cost, p_user_id)
        RETURNING id INTO v_po_id;

        INSERT INTO public.purchase_order_line_items (purchase_order_id, company_id, variant_id, quantity, cost)
        SELECT v_po_id, p_company_id, (s->>'variant_id')::uuid, (s->>'suggested_reorder_quantity')::integer, (s->>'unit_cost')::integer
        FROM jsonb_array_elements(suggestion) s;

        -- Log the creation of this PO in the audit log
        INSERT INTO public.audit_log (company_id, user_id, action, details)
        VALUES (
            p_company_id, 
            p_user_id, 
            'purchase_order_created', 
            jsonb_build_object(
                'po_id', v_po_id,
                'po_number', v_po_number,
                'supplier_name', supplier_name,
                'total_cost', v_total_cost,
                'item_count', jsonb_array_length(suggestion)
            )
        );

        created_po_count := created_po_count + 1;
    END LOOP;

    RETURN created_po_count;
END;
$$;


-- Function to record a sale and update inventory atomically
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid, -- Can be null for platform syncs
    p_customer_name text,
    p_customer_email text,
    p_payment_method text,
    p_notes text,
    p_sale_items jsonb, -- array of {sku, quantity, unit_price, cost_at_time}
    p_external_id text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_customer_id uuid;
    v_order_id uuid;
    item record;
    v_variant_id uuid;
    v_subtotal integer := 0;
    v_current_stock integer;
BEGIN
    -- 1. Find or create customer
    INSERT INTO customers (company_id, customer_name, email)
    VALUES (p_company_id, p_customer_name, p_customer_email)
    ON CONFLICT (company_id, email) DO UPDATE SET customer_name = p_customer_name
    RETURNING id INTO v_customer_id;

    -- 2. Calculate subtotal
    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(quantity int, unit_price int)
    LOOP
        v_subtotal := v_subtotal + (item.quantity * item.unit_price);
    END LOOP;

    -- 3. Create the order
    INSERT INTO orders (company_id, customer_id, order_number, total_amount, subtotal, source_platform, external_order_id, notes)
    VALUES (p_company_id, v_customer_id, 'SALE-' || extract(epoch from now()), v_subtotal, v_subtotal, 'manual', p_external_id, p_notes)
    RETURNING id INTO v_order_id;
    
    -- 4. Process line items and update inventory
    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, product_name text, quantity int, unit_price int, cost_at_time int)
    LOOP
        -- Find variant for the SKU
        SELECT pv.id INTO v_variant_id FROM product_variants pv WHERE pv.sku = item.sku AND pv.company_id = p_company_id;
        
        IF v_variant_id IS NULL THEN
            RAISE WARNING 'SKU % not found for sale, skipping inventory update.', item.sku;
        ELSE
            -- Lock the row and update inventory
            UPDATE product_variants
            SET inventory_quantity = inventory_quantity - item.quantity
            WHERE id = v_variant_id
            RETURNING inventory_quantity INTO v_current_stock;

            -- Log the inventory change
            INSERT INTO inventory_ledger(company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
            VALUES (p_company_id, v_variant_id, 'sale', -item.quantity, v_current_stock, v_order_id, 'Order ' || p_external_id);
        END IF;

        -- Insert the line item
        INSERT INTO order_line_items (order_id, company_id, variant_id, sku, product_name, quantity, price, cost_at_time)
        VALUES (v_order_id, p_company_id, v_variant_id, item.sku, item.product_name, item.quantity, item.unit_price, item.cost_at_time);
    END LOOP;

    RETURN v_order_id;
END;
$$;


-- Final data population and scheduling
-- This part is left for user-specific data or can be removed if not needed.
-- Example: Schedule a daily job to refresh materialized views
-- SELECT cron.schedule('refresh-views', '0 3 * * *', 'CALL public.refresh_all_materialized_views()');


-- Final check: Ensure service_role has necessary permissions on the vault schema
-- This might need to be run by a superuser if permissions are restricted.
DO $$
BEGIN
   IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'vault') THEN
      GRANT USAGE ON SCHEMA vault TO service_role;
      GRANT ALL ON ALL TABLES IN SCHEMA vault TO service_role;
   END IF;
END $$;
