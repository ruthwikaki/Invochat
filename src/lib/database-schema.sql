
-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Companies Table
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

-- Users Table (simple version, relies on auth.users for most data)
CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role text DEFAULT 'member',
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Company Settings
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days int NOT NULL DEFAULT 90,
    fast_moving_days int NOT NULL DEFAULT 30,
    overstock_multiplier int NOT NULL DEFAULT 3,
    high_value_threshold int NOT NULL DEFAULT 1000, -- in cents
    predictive_stock_days int NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric DEFAULT 0,
    custom_rules jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;

-- Products Table
CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
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
    updated_at timestamptz
);
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS fts_document tsvector;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX IF NOT EXISTS products_company_external_id_idx ON public.products (company_id, external_product_id);

-- Product Variants Table
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
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
    location text,
    external_variant_id text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX IF NOT EXISTS variants_company_sku_idx ON public.product_variants (company_id, sku);
CREATE UNIQUE INDEX IF NOT EXISTS variants_company_external_id_idx ON public.product_variants (company_id, external_variant_id);

-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text NOT NULL,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0, -- in cents
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

-- Orders Table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    status text NOT NULL DEFAULT 'pending',
    financial_status text DEFAULT 'pending',
    fulfillment_status text DEFAULT 'unfulfilled',
    currency text DEFAULT 'USD',
    subtotal integer NOT NULL DEFAULT 0,
    total_tax integer DEFAULT 0,
    total_shipping integer DEFAULT 0,
    total_discounts integer DEFAULT 0,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- Order Line Items
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    cost_at_time integer,
    external_line_item_id text
);
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;

-- Suppliers Table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

-- Purchase Orders
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status text NOT NULL DEFAULT 'Draft',
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX IF NOT EXISTS po_company_idempotency_idx ON public.purchase_orders (company_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS idempotency_key text;

-- Purchase Order Line Items
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id),
    quantity integer NOT NULL,
    cost integer NOT NULL
);
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;


-- Inventory Ledger
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;

-- Integrations
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;

-- Webhook Events (for deduplication)
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    processed_at timestamptz DEFAULT now(),
    created_at timestamptz DEFAULT now()
);
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX IF NOT EXISTS webhook_events_unique_idx ON public.webhook_events (integration_id, webhook_id);

-- Audit Log
CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigserial PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id),
    user_id uuid REFERENCES auth.users(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now()
);
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

-- Drop insecure legacy functions and policies if they exist
DROP VIEW IF EXISTS public.product_variants_with_details CASCADE;
DROP FUNCTION IF EXISTS public.get_my_company_id();

--
-- Security Functions
--
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id uuid)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT company_id FROM public.users WHERE id = p_user_id;
$$;

-- Function to handle new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (new.raw_app_meta_data->>'company_name')
  RETURNING id INTO new_company_id;

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
  WHERE id = new.id;

  -- Insert into our public users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, new.email, 'Owner');
  
  RETURN new;
END;
$$;

-- Trigger for new user signup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

--
-- Financial & Inventory Functions
--
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_customer_name text,
    p_customer_email text,
    p_payment_method text,
    p_notes text,
    p_sale_items jsonb[],
    p_external_id text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_customer_id uuid;
    v_order_id uuid;
    v_variant_id uuid;
    v_current_stock integer;
    v_item jsonb;
BEGIN
    -- Upsert customer
    INSERT INTO public.customers (company_id, customer_name, email)
    VALUES (p_company_id, p_customer_name, p_customer_email)
    ON CONFLICT (company_id, email) DO UPDATE
    SET customer_name = EXCLUDED.customer_name
    RETURNING id INTO v_customer_id;

    -- Create order
    INSERT INTO public.orders (company_id, customer_id, status, financial_status, order_number, external_order_id, total_amount)
    VALUES (p_company_id, v_customer_id, 'completed', 'paid', 'ORD-' || substr(uuid_generate_v4()::text, 1, 8), p_external_id, 0)
    RETURNING id INTO v_order_id;
    
    -- Process line items
    FOREACH v_item IN ARRAY p_sale_items
    LOOP
        -- Find variant
        SELECT id INTO v_variant_id FROM public.product_variants WHERE sku = v_item->>'sku' AND company_id = p_company_id;

        IF v_variant_id IS NULL THEN
            -- Optionally, handle SKUs not found
            CONTINUE;
        END IF;

        -- RACE CONDITION FIX: Lock the variant row to prevent concurrent updates
        SELECT inventory_quantity INTO v_current_stock FROM public.product_variants WHERE id = v_variant_id FOR UPDATE;

        -- Insert line item
        INSERT INTO public.order_line_items (order_id, company_id, variant_id, product_name, sku, quantity, price, cost_at_time)
        VALUES (
            v_order_id,
            p_company_id,
            v_variant_id,
            v_item->>'product_name',
            v_item->>'sku',
            (v_item->>'quantity')::integer,
            (v_item->>'unit_price')::integer,
            (v_item->>'cost_at_time')::integer
        );

        -- Update inventory quantity
        UPDATE public.product_variants SET inventory_quantity = v_current_stock - (v_item->>'quantity')::integer WHERE id = v_variant_id;

        -- Record in ledger
        INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
        VALUES (
            p_company_id,
            v_variant_id,
            'sale',
            -(v_item->>'quantity')::integer,
            v_current_stock - (v_item->>'quantity')::integer,
            v_order_id,
            'Order #' || (SELECT order_number FROM public.orders WHERE id = v_order_id)
        );
    END LOOP;

    -- Update order total
    UPDATE public.orders
    SET total_amount = (SELECT SUM(price * quantity) FROM public.order_line_items WHERE order_id = v_order_id)
    WHERE id = v_order_id;
    
    RETURN v_order_id;
END;
$$;


CREATE OR REPLACE FUNCTION public.create_purchase_orders_from_suggestions(
    p_company_id uuid,
    p_user_id uuid,
    p_suggestions jsonb[],
    p_idempotency_key text
)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    suggestion jsonb;
    supplier_map jsonb := '{}'::jsonb;
    po_map jsonb := '{}'::jsonb;
    v_supplier_id uuid;
    v_po_id uuid;
    v_total_cost integer;
    v_po_count integer := 0;
BEGIN
    -- Group suggestions by supplier
    FOREACH suggestion IN ARRAY p_suggestions
    LOOP
        v_supplier_id := (suggestion->>'supplier_id')::uuid;
        IF NOT (supplier_map ? v_supplier_id::text) THEN
            supplier_map := jsonb_set(supplier_map, ARRAY[v_supplier_id::text], '[]'::jsonb);
        END IF;
        supplier_map := jsonb_set(
            supplier_map,
            ARRAY[v_supplier_id::text],
            (supplier_map->v_supplier_id::text) || jsonb_build_array(suggestion)
        );
    END LOOP;
    
    -- Create one PO per supplier
    FOR v_supplier_id IN SELECT (jsonb_object_keys(supplier_map))::uuid
    LOOP
        -- Create the purchase order record
        INSERT INTO public.purchase_orders (company_id, supplier_id, status, po_number, total_cost, idempotency_key)
        VALUES (
            p_company_id,
            v_supplier_id,
            'Ordered',
            'PO-' || substr(uuid_generate_v4()::text, 1, 8),
            0,
            p_idempotency_key || '-' || v_supplier_id::text
        )
        RETURNING id INTO v_po_id;
        
        v_total_cost := 0;

        -- Add line items for this supplier's suggestions
        FOR suggestion IN SELECT * FROM jsonb_array_elements(supplier_map->v_supplier_id::text)
        LOOP
            INSERT INTO public.purchase_order_line_items (purchase_order_id, variant_id, quantity, cost)
            VALUES (
                v_po_id,
                (suggestion->>'variant_id')::uuid,
                (suggestion->>'suggested_reorder_quantity')::integer,
                (suggestion->>'unit_cost')::integer
            );
            v_total_cost := v_total_cost + ((suggestion->>'suggested_reorder_quantity')::integer * (suggestion->>'unit_cost')::integer);
        END LOOP;

        -- Update the total cost on the PO
        UPDATE public.purchase_orders SET total_cost = v_total_cost WHERE id = v_po_id;
        v_po_count := v_po_count + 1;
    END LOOP;

    RETURN v_po_count;
END;
$$;


-- Create the view again with the final, correct structure
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;

--
-- Row-Level Security Policies
--
CREATE POLICY "Allow company members to read" ON public.companies FOR SELECT USING (id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow user to read their own user data" ON public.users FOR SELECT USING (id = auth.uid());
CREATE POLICY "Allow user to manage their own company settings" ON public.company_settings FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to read products" ON public.products FOR SELECT USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to read variants" ON public.product_variants FOR SELECT USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to manage customers" ON public.customers FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to read orders" ON public.orders FOR SELECT USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to read order line items" ON public.order_line_items FOR SELECT USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to manage suppliers" ON public.suppliers FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to manage purchase orders" ON public.purchase_orders FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to read ledger" ON public.inventory_ledger FOR SELECT USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow company members to manage integrations" ON public.integrations FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "Allow admins to read audit logs for their company" ON public.audit_log FOR SELECT USING (company_id = public.get_company_id_for_user(auth.uid()) AND (SELECT role FROM public.users WHERE id = auth.uid()) = 'Admin');
