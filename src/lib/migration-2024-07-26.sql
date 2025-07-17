-- InvoChat Advanced Database Migration
-- July 26, 2024
--
-- This script applies several critical fixes and improvements to an existing InvoChat database.
-- It addresses security, performance, and data integrity issues.

-- --- UTILITY FUNCTIONS ---
-- A function to safely drop RLS policies if they exist.
CREATE OR REPLACE FUNCTION drop_all_rls_policies(schema_name TEXT)
RETURNS void AS $$
DECLARE
    tbl RECORD;
BEGIN
    FOR tbl IN
        SELECT tablename FROM pg_tables WHERE schemaname = schema_name
    LOOP
        -- Specifically drop the policy we are about to create, if it exists
        EXECUTE format('DROP POLICY IF EXISTS "Allow all access to own company data" ON %I.%I;', schema_name, tbl.tablename);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- A function to re-apply RLS policies to all tables.
CREATE OR REPLACE FUNCTION enable_rls_for_all_tables(schema_name TEXT)
RETURNS void AS $$
DECLARE
    tbl RECORD;
BEGIN
    FOR tbl IN
        SELECT tablename FROM pg_tables WHERE schemaname = schema_name
    LOOP
        -- Special case for the 'companies' table itself
        IF tbl.tablename = 'companies' THEN
            EXECUTE format('CREATE POLICY "Allow all access to own company data" ON public.%I FOR ALL USING (id = public.get_company_id());', tbl.tablename);
        -- Special case for webhook_events which links through integrations
        ELSIF tbl.tablename = 'webhook_events' THEN
            EXECUTE format(
                'CREATE POLICY "Allow all access to own company data" ON public.%I FOR ALL USING ((EXISTS ( SELECT 1 FROM public.integrations i WHERE ((i.id = %I.integration_id) AND (i.company_id = public.get_company_id())))));',
                tbl.tablename, tbl.tablename
            );
        ELSE
            EXECUTE format('CREATE POLICY "Allow all access to own company data" ON public.%I FOR ALL USING (company_id = public.get_company_id());', tbl.tablename);
        END IF;

        EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY;', schema_name, tbl.tablename);
    END LOOP;
END;
$$ LANGUAGE plpgsql;


-- --- MIGRATION START ---
BEGIN;

-- STEP 1: PREPARE FOR MIGRATION
-- Drop existing views and functions that will be modified.
-- This must be done first to avoid dependency errors.
SELECT drop_all_rls_policies('public');

DROP VIEW IF EXISTS public.orders_view;
DROP VIEW IF EXISTS public.customers_view;
DROP VIEW IF EXISTS public.product_variants_with_details;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

DROP FUNCTION IF EXISTS public.get_company_id();
DROP FUNCTION IF EXISTS public.handle_new_user();

-- STEP 2: FIX CORE FUNCTIONS
-- Recreate get_company_id with better security (no SECURITY DEFINER).
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS UUID AS $$
BEGIN
    RETURN (current_setting('request.jwt.claims', true)::jsonb ->> 'company_id')::UUID;
END;
$$ LANGUAGE plpgsql STABLE;

-- Recreate handle_new_user to be more robust.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    v_company_id UUID;
    v_company_name TEXT := new.raw_app_meta_data ->> 'company_name';
BEGIN
    -- Create the company and get its ID
    INSERT INTO public.companies (name) VALUES (v_company_name)
    RETURNING id INTO v_company_id;

    -- Create a corresponding user profile in the public schema
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new.id, v_company_id, new.email, 'Owner');

    -- Update the user's app_metadata in the auth schema with the new company_id
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'role', 'Owner')
    WHERE id = new.id;
    
    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-create the trigger for new user creation
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- STEP 3: APPLY SCHEMA CHANGES AND CONSTRAINTS
-- Add missing columns and constraints, ensuring idempotency.

-- Add company_id to product_variants if it doesn't exist
ALTER TABLE public.product_variants
ADD COLUMN IF NOT EXISTS company_id UUID;

-- Add idempotency_key to purchase_orders if it doesn't exist
ALTER TABLE public.purchase_orders
ADD COLUMN IF NOT EXISTS idempotency_key UUID;

-- Drop constraints if they exist, then add them.
ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS product_variants_company_id_fkey;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_customer_id_fkey;
ALTER TABLE public.orders ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL;

ALTER TABLE public.order_line_items DROP CONSTRAINT IF EXISTS order_line_items_order_id_fkey;
ALTER TABLE public.order_line_items ADD CONSTRAINT order_line_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;

ALTER TABLE public.order_line_items DROP CONSTRAINT IF EXISTS order_line_items_variant_id_fkey;
ALTER TABLE public.order_line_items ADD CONSTRAINT order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;

ALTER TABLE public.purchase_orders DROP CONSTRAINT IF EXISTS purchase_orders_supplier_id_fkey;
ALTER TABLE public.purchase_orders ADD CONSTRAINT purchase_orders_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;

ALTER TABLE public.purchase_order_line_items DROP CONSTRAINT IF EXISTS purchase_order_line_items_purchase_order_id_fkey;
ALTER TABLE public.purchase_order_line_items ADD CONSTRAINT purchase_order_line_items_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES public.purchase_orders(id) ON DELETE CASCADE;

ALTER TABLE public.purchase_order_line_items DROP CONSTRAINT IF EXISTS purchase_order_line_items_variant_id_fkey;
ALTER TABLE public.purchase_order_line_items ADD CONSTRAINT purchase_order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE CASCADE;


-- STEP 4: RECREATE VIEWS with corrected definitions
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    pv.company_id,
    p.title AS product_title,
    pv.title AS variant_title,
    pv.sku,
    pv.price,
    pv.cost,
    pv.inventory_quantity,
    p.status AS product_status,
    p.image_url
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;

CREATE OR REPLACE VIEW public.customers_view AS
SELECT
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    c.total_orders,
    c.total_spent,
    c.first_order_date,
    c.created_at
FROM
    public.customers c;

CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.*,
    c.customer_name
FROM
    public.orders o
LEFT JOIN
    public.customers c ON o.customer_id = c.id;


-- STEP 5: RE-ENABLE RLS
-- This runs the function defined at the start to apply policies to all tables.
SELECT enable_rls_for_all_tables('public');

-- STEP 6: CREATE INDEXES for performance
-- Create indexes only if they do not already exist.
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_company_id ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS idx_po_line_items_po_id ON public.purchase_order_line_items(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_po_line_items_variant_id ON public.purchase_order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations(company_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON public.conversations(user_id);


-- --- FIX INVENTORY RACE CONDITION ---
-- Replace the old `record_sale_transaction` with a new version that uses row-level locking.
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id UUID,
    p_user_id UUID,
    p_customer_name TEXT,
    p_customer_email TEXT,
    p_payment_method TEXT,
    p_notes TEXT,
    p_sale_items JSONB[],
    p_external_id TEXT DEFAULT NULL
) RETURNS VOID AS $$
DECLARE
    v_customer_id UUID;
    v_order_id UUID;
    v_total_amount INT := 0;
    sale_item RECORD;
    v_variant_id UUID;
    v_current_quantity INT;
BEGIN
    -- Get or create the customer
    SELECT id INTO v_customer_id FROM customers WHERE email = p_customer_email AND company_id = p_company_id;
    IF v_customer_id IS NULL THEN
        INSERT INTO customers (company_id, customer_name, email)
        VALUES (p_company_id, p_customer_name, p_customer_email)
        RETURNING id INTO v_customer_id;
    END IF;

    -- Create the order
    INSERT INTO orders (company_id, customer_id, financial_status, total_amount, external_order_id, source_platform)
    VALUES (p_company_id, v_customer_id, 'paid', 0, p_external_id, 'manual')
    RETURNING id INTO v_order_id;

    -- Process each line item
    FOR sale_item IN SELECT * FROM jsonb_to_recordset(array_to_json(p_sale_items)::jsonb) AS x(sku TEXT, product_name TEXT, quantity INT, unit_price INT, cost_at_time INT)
    LOOP
        -- Find the variant_id for the given SKU
        SELECT id INTO v_variant_id FROM product_variants WHERE sku = sale_item.sku AND company_id = p_company_id;

        IF v_variant_id IS NOT NULL THEN
            -- **CRITICAL**: Lock the variant row to prevent race conditions
            SELECT inventory_quantity INTO v_current_quantity FROM product_variants WHERE id = v_variant_id FOR UPDATE;

            -- Update inventory quantity
            UPDATE product_variants SET inventory_quantity = v_current_quantity - sale_item.quantity WHERE id = v_variant_id;

            -- Insert into inventory ledger
            INSERT INTO inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
            VALUES (p_company_id, v_variant_id, 'sale', -sale_item.quantity, v_current_quantity - sale_item.quantity, v_order_id, 'Sale recorded');
            
            -- Insert into order_line_items
            INSERT INTO order_line_items (order_id, variant_id, product_name, sku, quantity, price, cost_at_time, company_id)
            VALUES (v_order_id, v_variant_id, sale_item.product_name, sale_item.sku, sale_item.quantity, sale_item.unit_price, sale_item.cost_at_time, p_company_id);

            v_total_amount := v_total_amount + (sale_item.quantity * sale_item.unit_price);
        END IF;
    END LOOP;

    -- Update the total amount on the order
    UPDATE orders SET total_amount = v_total_amount WHERE id = v_order_id;
END;
$$ LANGUAGE plpgsql;


-- Final commit of the transaction
COMMIT;
