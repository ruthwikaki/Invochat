
-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable vector extension
CREATE EXTENSION IF NOT EXISTS "vector";

-- Supabase AI is experimental and may not be available in all projects.
-- CREATE EXTENSION IF NOT EXISTS "supabase_ai";

-- Enable pg_tle
-- CREATE EXTENSION IF NOT EXISTS "pg_tle";

-- Enable PostGIS
-- CREATE EXTENSION IF NOT EXISTS "postgis" CASCADE;

-- This is a placeholder for your custom database schema.
-- It's a good practice to keep your database schema in a separate file.

-- ----------------------------------------------------------------
-- Schema: public
-- Tables for core business logic
-- ----------------------------------------------------------------

-- Companies Table: Stores information about each company (tenant)
CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.companies IS 'Stores information about each company (tenant) in the system.';

-- Users Table: Stores user information, linking them to a company
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email TEXT,
    role TEXT DEFAULT 'member',
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);
COMMENT ON TABLE public.users IS 'Stores application-specific user data, linking them to a company.';

-- Company Settings Table: Configurable business logic parameters for each company
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    overstock_multiplier INT NOT NULL DEFAULT 3,
    high_value_threshold INT NOT NULL DEFAULT 1000, -- in cents
    predictive_stock_days INT NOT NULL DEFAULT 7,
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    tax_rate NUMERIC DEFAULT 0.0,
    custom_rules JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    subscription_status TEXT DEFAULT 'trial',
    subscription_plan TEXT DEFAULT 'starter',
    subscription_expires_at TIMESTAMPTZ,
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    promo_sales_lift_multiplier REAL NOT NULL DEFAULT 2.5
);
COMMENT ON TABLE public.company_settings IS 'Configurable business logic parameters for each company.';

-- Integrations Table: Stores connection details for third-party platforms
CREATE TABLE IF NOT EXISTS public.integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT false,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS integrations_company_platform_idx ON public.integrations (company_id, platform);
COMMENT ON TABLE public.integrations IS 'Stores connection details for third-party platforms like Shopify, WooCommerce.';

-- Products Table: Central repository for product information
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    handle TEXT,
    product_type TEXT,
    tags TEXT[],
    status TEXT,
    image_url TEXT,
    external_product_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    fts_document TSVECTOR
);
CREATE UNIQUE INDEX IF NOT EXISTS products_company_external_id_idx ON public.products (company_id, external_product_id);
CREATE INDEX IF NOT EXISTS products_company_id_idx ON public.products (company_id);
CREATE INDEX IF NOT EXISTS products_fts_document_idx ON public.products USING GIN (fts_document);
COMMENT ON TABLE public.products IS 'Central repository for base product information.';

-- Product Variants Table: Specific variations of a product (e.g., size, color)
CREATE TABLE IF NOT EXISTS public.product_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    title TEXT,
    option1_name TEXT,
    option1_value TEXT,
    option2_name TEXT,
    option2_value TEXT,
    option3_name TEXT,
    option3_value TEXT,
    barcode TEXT,
    price INT, -- in cents
    compare_at_price INT, -- in cents
    cost INT, -- in cents
    inventory_quantity INT NOT NULL DEFAULT 0,
    location TEXT,
    external_variant_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS variants_company_sku_idx ON public.product_variants (company_id, sku);
CREATE UNIQUE INDEX IF NOT EXISTS variants_company_external_id_idx ON public.product_variants (company_id, external_variant_id);
CREATE INDEX IF NOT EXISTS variants_product_id_idx ON public.product_variants (product_id);
CREATE INDEX IF NOT EXISTS variants_company_id_quantity_idx ON public.product_variants (company_id, inventory_quantity);
COMMENT ON TABLE public.product_variants IS 'Specific variations of a product, representing the stock-keeping unit (SKU).';


-- Inventory Ledger Table: Transactional log of all inventory movements
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL, -- e.g., 'sale', 'purchase_order_received', 'reconciliation', 'manual_adjustment'
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID, -- Foreign key to orders, purchase_orders etc.
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS inventory_ledger_company_variant_idx ON public.inventory_ledger (company_id, variant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS inventory_ledger_change_type_idx ON public.inventory_ledger (change_type);
COMMENT ON TABLE public.inventory_ledger IS 'Transactional log of all inventory movements for auditing purposes.';

-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name TEXT NOT NULL,
    email TEXT,
    total_orders INT DEFAULT 0,
    total_spent INT DEFAULT 0, -- in cents
    first_order_date DATE,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS customers_company_email_idx ON public.customers (company_id, email);
COMMENT ON TABLE public.customers IS 'Stores customer information.';

-- Orders Table
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES public.customers(id),
    financial_status TEXT DEFAULT 'pending',
    fulfillment_status TEXT DEFAULT 'unfulfilled',
    currency TEXT DEFAULT 'USD',
    subtotal INT NOT NULL DEFAULT 0, -- in cents
    total_tax INT DEFAULT 0,
    total_shipping INT DEFAULT 0,
    total_discounts INT DEFAULT 0,
    total_amount INT NOT NULL,
    source_platform TEXT,
    source_name TEXT,
    tags TEXT[],
    notes TEXT,
    cancelled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS orders_company_created_at_idx ON public.orders (company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS orders_customer_id_idx ON public.orders (customer_id);
COMMENT ON TABLE public.orders IS 'Stores sales order information from all integrated platforms.';

-- Order Line Items Table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id),
    product_name TEXT NOT NULL,
    variant_title TEXT,
    sku TEXT NOT NULL,
    quantity INT NOT NULL,
    price INT NOT NULL, -- in cents
    total_discount INT DEFAULT 0,
    tax_amount INT DEFAULT 0,
    cost_at_time INT,
    external_line_item_id TEXT
);
COMMENT ON TABLE public.order_line_items IS 'Stores individual line items for each sales order.';

-- Suppliers Table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.suppliers IS 'Stores information about product suppliers/vendors.';

-- Purchase Orders Table
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.suppliers(id),
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INT NOT NULL, -- in cents
    expected_arrival_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    idempotency_key UUID
);
CREATE UNIQUE INDEX IF NOT EXISTS po_idempotency_key_idx ON public.purchase_orders (idempotency_key) WHERE idempotency_key IS NOT NULL;
COMMENT ON TABLE public.purchase_orders IS 'Stores purchase orders for replenishing stock.';

-- Purchase Order Line Items Table
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id),
    quantity INT NOT NULL,
    cost INT NOT NULL -- in cents
);
COMMENT ON TABLE public.purchase_order_line_items IS 'Stores individual line items for each purchase order.';

-- Webhook Events Table: For replay attack prevention
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    processed_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS webhook_events_integration_webhook_id_idx ON public.webhook_events (integration_id, webhook_id);
COMMENT ON TABLE public.webhook_events IS 'Logs processed webhook IDs to prevent replay attacks.';

-- Audit Log Table
CREATE TABLE IF NOT EXISTS public.audit_log (
    id BIGSERIAL PRIMARY KEY,
    company_id UUID REFERENCES public.companies(id),
    user_id UUID REFERENCES auth.users(id),
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);
COMMENT ON TABLE public.audit_log IS 'Records significant events and actions within the system for security and auditing.';

-- Export Jobs Table
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id UUID NOT NULL REFERENCES auth.users(id),
    status TEXT NOT NULL DEFAULT 'pending',
    download_url TEXT,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.export_jobs IS 'Tracks asynchronous data export jobs.';


-- ----------------------------------------------------------------
-- VIEWS: Denormalized data for easier querying
-- ----------------------------------------------------------------

-- View for product variants with essential product details joined
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    pv.company_id,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type,
    pv.sku,
    pv.title,
    pv.price,
    pv.cost,
    pv.inventory_quantity
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id AND pv.company_id = p.company_id;

-- View for orders with customer email
CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.*,
    c.email AS customer_email
FROM
    public.orders o
LEFT JOIN
    public.customers c ON o.customer_id = c.id;

-- View for customers with aggregated sales data
CREATE OR REPLACE VIEW public.customers_view AS
SELECT
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    c.total_orders,
    c.total_spent,
    c.first_order_date,
    c.deleted_at,
    c.created_at
FROM
    public.customers c
WHERE
    c.deleted_at IS NULL;

-- ----------------------------------------------------------------
-- Stored Procedures and Functions
-- ----------------------------------------------------------------

-- Function to get current user's company_id from the JWT claims
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT nullif(current_setting('app.current_company_id', true), '')::UUID;
$$;


-- Procedure to enable RLS on a table and apply a standard company_id policy
CREATE OR REPLACE PROCEDURE public.enable_rls_on_table(p_table_name TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', p_table_name);
    EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY;', p_table_name);
    EXECUTE format('DROP POLICY IF EXISTS "Allow all access to own company data" ON public.%I;', p_table_name);
    EXECUTE format(
        'CREATE POLICY "Allow all access to own company data" ON public.%I ' ||
        'FOR ALL USING (company_id = public.get_company_id());',
        p_table_name
    );
END;
$$;


-- Automatically handle new user sign-ups
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_company_id UUID;
    user_company_name TEXT;
    user_role TEXT;
BEGIN
    -- Check for company_name in auth.users.raw_app_meta_data
    user_company_name := new.raw_app_meta_data->>'company_name';
    user_role := 'Owner';

    -- Insert a new company and get its ID
    INSERT INTO public.companies (name)
    VALUES (user_company_name)
    RETURNING id INTO new_company_id;

    -- Insert into public.users
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new.id, new_company_id, new.email, user_role);

    -- Update the user's app_metadata in auth.users
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', user_role)
    WHERE id = new.id;

    RETURN new;
END;
$$;

-- Trigger for handle_new_user
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- Function to record a sale and update inventory atomically
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id UUID,
    p_user_id UUID,
    p_customer_name TEXT,
    p_customer_email TEXT,
    p_payment_method TEXT,
    p_notes TEXT,
    p_sale_items JSONB[],
    p_external_id TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_customer_id UUID;
    v_order_id UUID;
    v_total_amount INT := 0;
    v_variant_id UUID;
    v_current_stock INT;
    item JSONB;
    p_sku TEXT;
    p_quantity INT;
    p_unit_price INT;
BEGIN
    -- Find or create customer
    SELECT id INTO v_customer_id FROM public.customers
    WHERE company_id = p_company_id AND email = p_customer_email;

    IF v_customer_id IS NULL THEN
        INSERT INTO public.customers (company_id, customer_name, email)
        VALUES (p_company_id, p_customer_name, p_customer_email)
        RETURNING id INTO v_customer_id;
    END IF;

    -- Calculate total amount
    FOREACH item IN ARRAY p_sale_items
    LOOP
        v_total_amount := v_total_amount + ((item->>'quantity')::INT * (item->>'unit_price')::INT);
    END LOOP;

    -- Create order
    INSERT INTO public.orders (company_id, customer_id, total_amount, notes, order_number, external_order_id)
    VALUES (p_company_id, v_customer_id, v_total_amount, p_notes, 'ORD-' || nextval('orders_order_number_seq'), p_external_id)
    RETURNING id INTO v_order_id;

    -- Process line items
    FOREACH item IN ARRAY p_sale_items
    LOOP
        p_sku := item->>'sku';
        p_quantity := (item->>'quantity')::INT;
        p_unit_price := (item->>'unit_price')::INT;
        
        -- Get variant_id and lock the row for update
        SELECT id, inventory_quantity INTO v_variant_id, v_current_stock
        FROM public.product_variants
        WHERE company_id = p_company_id AND sku = p_sku
        FOR UPDATE;
        
        IF v_variant_id IS NULL THEN
            RAISE EXCEPTION 'Product with SKU % not found', p_sku;
        END IF;

        IF v_current_stock < p_quantity THEN
            RAISE EXCEPTION 'Insufficient stock for SKU %: requested %, available %', p_sku, p_quantity, v_current_stock;
        END IF;

        -- Insert line item
        INSERT INTO public.order_line_items (order_id, company_id, variant_id, product_name, sku, quantity, price)
        VALUES (v_order_id, p_company_id, v_variant_id, item->>'product_name', p_sku, p_quantity, p_unit_price);

        -- Update inventory
        UPDATE public.product_variants
        SET inventory_quantity = inventory_quantity - p_quantity
        WHERE id = v_variant_id;

        -- Create ledger entry
        INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
        VALUES (p_company_id, v_variant_id, 'sale', -p_quantity, v_current_stock - p_quantity, v_order_id, 'Order ' || (SELECT order_number FROM orders WHERE id=v_order_id));
    END LOOP;

    -- Record in audit log
    INSERT INTO public.audit_log (company_id, user_id, action, details)
    VALUES (p_company_id, p_user_id, 'record_sale', jsonb_build_object('order_id', v_order_id));

    RETURN v_order_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_order_from_platform(
    p_company_id UUID,
    p_order_payload JSONB,
    p_platform TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_customer_id UUID;
    v_order_id UUID;
    line_item JSONB;
    v_variant_id UUID;
    v_sku TEXT;
    v_quantity INT;
    v_current_stock INT;
    v_financial_status TEXT;
    v_customer_email TEXT;
BEGIN
    v_customer_email := p_order_payload->'customer'->>'email';
    -- Find or create customer
    SELECT id INTO v_customer_id FROM public.customers
    WHERE company_id = p_company_id AND email = v_customer_email;

    IF v_customer_id IS NULL THEN
        INSERT INTO public.customers (company_id, customer_name, email)
        VALUES (p_company_id, 
                p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name',
                v_customer_email)
        RETURNING id INTO v_customer_id;
    END IF;

    -- Determine financial status for Shopify
    IF p_platform = 'shopify' THEN
        v_financial_status := p_order_payload->>'financial_status';
    ELSE
        v_financial_status := p_order_payload->>'status';
    END IF;

    -- Insert the order
    INSERT INTO public.orders (
        company_id, external_order_id, order_number, customer_id, financial_status,
        fulfillment_status, total_amount, created_at, source_platform
    )
    VALUES (
        p_company_id,
        p_order_payload->>'id',
        p_order_payload->>'name',
        v_customer_id,
        v_financial_status,
        p_order_payload->>'fulfillment_status',
        ( (p_order_payload->>'total_price')::NUMERIC * 100 )::INT,
        (p_order_payload->>'created_at')::TIMESTAMPTZ,
        p_platform
    )
    ON CONFLICT (company_id, external_order_id) DO NOTHING
    RETURNING id INTO v_order_id;
    
    -- If order already existed, do nothing further
    IF v_order_id IS NULL THEN
        RETURN;
    END IF;

    -- Loop through line items to update stock
    FOR line_item IN SELECT * FROM jsonb_array_elements(p_order_payload->'line_items')
    LOOP
        v_sku := line_item->>'sku';
        v_quantity := (line_item->>'quantity')::INT;

        -- Lock variant and update inventory
        SELECT id, inventory_quantity INTO v_variant_id, v_current_stock
        FROM public.product_variants
        WHERE company_id = p_company_id AND sku = v_sku
        FOR UPDATE;
        
        -- If SKU exists, update inventory and log it
        IF v_variant_id IS NOT NULL THEN
            UPDATE public.product_variants
            SET inventory_quantity = inventory_quantity - v_quantity
            WHERE id = v_variant_id;

            INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
            VALUES (p_company_id, v_variant_id, 'sale', -v_quantity, v_current_stock - v_quantity, v_order_id, 'Order ' || (p_order_payload->>'name'));
        ELSE
             -- Log a warning or handle cases where the SKU from the order doesn't exist in our DB
             INSERT INTO public.audit_log(company_id, action, details) VALUES (p_company_id, 'sync_warning', jsonb_build_object('order_id', v_order_id, 'message', 'SKU not found during order sync', 'sku', v_sku));
        END IF;

    END LOOP;
END;
$$;


CREATE OR REPLACE FUNCTION public.create_purchase_orders_from_suggestions(
    p_company_id UUID,
    p_user_id UUID,
    p_suggestions JSONB,
    p_idempotency_key UUID
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    suggestion JSONB;
    grouped_suggestions JSONB;
    supplier_id_key UUID;
    v_po_id UUID;
    v_total_cost INT;
    v_po_number TEXT;
    v_created_po_count INT := 0;
BEGIN
    -- Group suggestions by supplier_id
    SELECT jsonb_object_agg(s->>'supplier_id', jsonb_agg(s))
    INTO grouped_suggestions
    FROM jsonb_array_elements(p_suggestions) s;

    IF grouped_suggestions IS NULL THEN
        RETURN 0;
    END IF;

    -- Loop through each supplier group
    FOR supplier_id_key IN SELECT (k::TEXT)::UUID FROM jsonb_object_keys(grouped_suggestions) k
    LOOP
        v_total_cost := 0;
        
        -- Calculate total cost for the PO
        FOR suggestion IN SELECT * FROM jsonb_array_elements(grouped_suggestions->>(supplier_id_key::TEXT))
        LOOP
            v_total_cost := v_total_cost + ((suggestion->>'suggested_reorder_quantity')::INT * (suggestion->>'unit_cost')::INT);
        END LOOP;

        v_po_number := 'PO-' || to_char(now(), 'YYYYMMDD') || '-' || (SELECT count(*) + 1 FROM purchase_orders WHERE company_id = p_company_id AND created_at >= date_trunc('day', now()));

        -- Create the Purchase Order
        INSERT INTO public.purchase_orders (company_id, supplier_id, status, po_number, total_cost, idempotency_key)
        VALUES (p_company_id, supplier_id_key, 'Draft', v_po_number, v_total_cost, p_idempotency_key)
        RETURNING id INTO v_po_id;

        -- Create PO Line Items
        FOR suggestion IN SELECT * FROM jsonb_array_elements(grouped_suggestions->>(supplier_id_key::TEXT))
        LOOP
            INSERT INTO public.purchase_order_line_items (purchase_order_id, company_id, variant_id, quantity, cost)
            VALUES (v_po_id, p_company_id, (suggestion->>'variant_id')::UUID, (suggestion->>'suggested_reorder_quantity')::INT, (suggestion->>'unit_cost')::INT);
        END LOOP;
        
        v_created_po_count := v_created_po_count + 1;
        
        -- Audit Log
        INSERT INTO public.audit_log (company_id, user_id, action, details)
        VALUES (p_company_id, p_user_id, 'create_purchase_order', jsonb_build_object('purchase_order_id', v_po_id, 'source', 'suggestion'));

    END LOOP;

    RETURN v_created_po_count;
END;
$$;


-- ----------------------------------------------------------------
-- RLS (Row Level Security)
-- ----------------------------------------------------------------

-- Enable RLS for all tables
DO $$
DECLARE
    t_name TEXT;
BEGIN
    FOR t_name IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public')
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS "Allow all access to own company data" ON public.' || quote_ident(t_name) || ';';
        EXECUTE 'ALTER TABLE public.' || quote_ident(t_name) || ' ENABLE ROW LEVEL SECURITY;';
        EXECUTE 'ALTER TABLE public.' || quote_ident(t_name) || ' FORCE ROW LEVEL SECURITY;';
        EXECUTE 'CREATE POLICY "Allow all access to own company data" ON public.' || quote_ident(t_name) || 
                ' FOR ALL USING (company_id = public.get_company_id());';
    END LOOP;
END;
$$;

-- Special RLS for the users table
DROP POLICY IF EXISTS "Allow users to see themselves" ON public.users;
CREATE POLICY "Allow users to see themselves" ON public.users
FOR SELECT USING (id = auth.uid());

-- Special RLS for the companies table
DROP POLICY IF EXISTS "Allow users to see their own company" ON public.companies;
CREATE POLICY "Allow users to see their own company" ON public.companies
FOR SELECT USING (id = public.get_company_id());

-- Grant usage on schema and all tables to authenticated users
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;


-- Finally, refresh materialized views if they exist
DO $$
BEGIN
   IF EXISTS (SELECT FROM pg_matviews WHERE matviewname = 'daily_sales_stats') THEN
      REFRESH MATERIALIZED VIEW public.daily_sales_stats;
   END IF;
   IF EXISTS (SELECT FROM pg_matviews WHERE matviewname = 'product_profit_stats') THEN
      REFRESH MATERIALIZED VIEW public.product_profit_stats;
   END IF;
END $$;
