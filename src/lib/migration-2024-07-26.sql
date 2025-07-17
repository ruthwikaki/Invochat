
-- ### InvoChat Database Migration ###
-- Date: 2024-07-26
-- This script migrates an existing database to the latest schema version.
-- DO NOT RUN THIS ON A NEW SETUP. Use database-schema.sql for new setups.

-- #### Transaction Start ####
BEGIN;

-- #### Step 1: Drop dependent views and functions ####
-- We must drop objects that depend on the columns or functions we are about to change.

DROP VIEW IF EXISTS public.orders_view;
DROP VIEW IF EXISTS public.customers_view;
DROP PROCEDURE IF EXISTS enable_rls_on_table(text);
DROP FUNCTION IF EXISTS public.record_sale_transaction(uuid, uuid, text, text, text, text, jsonb[], text);


-- #### Step 2: Drop all existing RLS policies ####
-- We will re-create these later with a more secure and consistent definition.
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT policyname, tablename FROM pg_policies WHERE schemaname = 'public') LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.' || quote_ident(r.tablename);
    END LOOP;
END;
$$;

-- #### Step 3: Modify the get_company_id() function ####
-- We are making this function more secure and performant.
-- Drop the old function before creating the new one.
DROP FUNCTION IF EXISTS public.get_company_id();
CREATE OR REPLACE FUNCTION get_company_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
BEGIN
  RETURN current_setting('app.current_company_id', true)::uuid;
EXCEPTION
  WHEN others THEN
    RETURN NULL;
END;
$$;


-- #### Step 4: Add new tables that were missing ####

CREATE TABLE IF NOT EXISTS public.discounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    type TEXT NOT NULL,
    value INT NOT NULL,
    minimum_purchase INT,
    usage_limit INT,
    usage_count INT DEFAULT 0,
    applies_to TEXT DEFAULT 'all',
    starts_at TIMESTAMPTZ,
    ends_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.customer_addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    address_type TEXT NOT NULL DEFAULT 'shipping',
    first_name TEXT,
    last_name TEXT,
    company TEXT,
    address1 TEXT,
    address2 TEXT,
    city TEXT,
    province_code TEXT,
    country_code TEXT,
    zip TEXT,
    phone TEXT,
    is_default BOOLEAN DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.refunds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES public.orders(id),
    refund_number TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    reason TEXT,
    note TEXT,
    total_amount INT NOT NULL,
    created_by_user_id UUID REFERENCES auth.users(id),
    external_refund_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.refund_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    refund_id UUID NOT NULL REFERENCES public.refunds(id) ON DELETE CASCADE,
    order_line_item_id UUID NOT NULL REFERENCES public.order_line_items(id),
    quantity INT NOT NULL,
    amount INT NOT NULL,
    restock BOOLEAN DEFAULT true,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS public.webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    processed_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_webhook_events_id ON public.webhook_events (integration_id, webhook_id);

-- #### Step 5: Alter existing tables to fix inconsistencies and add constraints ####

-- Add idempotency key to purchase orders
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS idempotency_key UUID;
CREATE UNIQUE INDEX IF NOT EXISTS uq_po_idempotency ON public.purchase_orders (idempotency_key) WHERE idempotency_key IS NOT NULL;

-- Make order_line_items.sku NOT NULL
ALTER TABLE public.order_line_items ALTER COLUMN sku SET NOT NULL;
ALTER TABLE public.order_line_items ALTER COLUMN product_name SET NOT NULL;

-- Add foreign key from product_variants to companies table that might be missing
ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS product_variants_company_id_fkey;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_company_id_fkey
    FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

-- Drop the unused status column from orders
ALTER TABLE public.orders DROP COLUMN IF EXISTS status;

-- #### Step 6: Recreate Views and Functions ####

-- Recreate the function to record sales with locking to prevent race conditions.
CREATE OR REPLACE FUNCTION record_sale_transaction(
    p_company_id UUID,
    p_user_id UUID,
    p_customer_name TEXT,
    p_customer_email TEXT,
    p_payment_method TEXT,
    p_notes TEXT,
    p_sale_items JSONB[],
    p_external_id TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_customer_id UUID;
    v_order_id UUID;
    v_total_amount INT := 0;
    v_item RECORD;
    v_variant RECORD;
BEGIN
    SELECT id INTO v_customer_id FROM customers WHERE company_id = p_company_id AND email = p_customer_email;
    IF v_customer_id IS NULL THEN
        INSERT INTO customers (company_id, customer_name, email)
        VALUES (p_company_id, p_customer_name, p_customer_email)
        RETURNING id INTO v_customer_id;
    END IF;

    INSERT INTO orders (company_id, customer_id, total_amount, notes, external_order_id, fulfillment_status, financial_status, order_number)
    VALUES (p_company_id, v_customer_id, 0, p_notes, p_external_id, 'unfulfilled', 'paid', 'SALE-' || nextval('orders_order_number_seq'))
    RETURNING id INTO v_order_id;
    
    FOR v_item IN SELECT * FROM jsonb_to_recordset(array_to_json(p_sale_items)::jsonb) AS x(sku TEXT, product_name TEXT, quantity INT, unit_price INT, cost_at_time INT)
    LOOP
        SELECT id, inventory_quantity INTO v_variant FROM product_variants
        WHERE company_id = p_company_id AND sku = v_item.sku FOR UPDATE;
        
        IF v_variant IS NULL THEN RAISE EXCEPTION 'Product with SKU % not found', v_item.sku; END IF;
        IF v_variant.inventory_quantity < v_item.quantity THEN RAISE EXCEPTION 'Not enough stock for SKU %. Available: %, Required: %', v_item.sku, v_variant.inventory_quantity, v_item.quantity; END IF;

        UPDATE product_variants SET inventory_quantity = inventory_quantity - v_item.quantity WHERE id = v_variant.id;
        
        INSERT INTO order_line_items (order_id, company_id, variant_id, product_name, sku, quantity, price, cost_at_time)
        VALUES (v_order_id, p_company_id, v_variant.id, v_item.product_name, v_item.sku, v_item.quantity, v_item.unit_price, v_item.cost_at_time);
        
        INSERT INTO inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id)
        VALUES (p_company_id, v_variant.id, 'sale', -v_item.quantity, v_variant.inventory_quantity - v_item.quantity, v_order_id);

        v_total_amount := v_total_amount + (v_item.quantity * v_item.unit_price);
    END LOOP;

    UPDATE orders SET total_amount = v_total_amount WHERE id = v_order_id;
    RETURN v_order_id;
END;
$$;


-- Recreate the views with the updated schema
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
    o.id,
    o.company_id,
    o.order_number,
    o.external_order_id,
    o.created_at,
    o.total_amount,
    o.fulfillment_status,
    o.financial_status,
    o.source_platform,
    c.email AS customer_email
FROM
    public.orders o
LEFT JOIN
    public.customers c ON o.customer_id = c.id;


-- #### Step 7: Re-enable RLS on all tables ####
CREATE OR REPLACE PROCEDURE enable_rls_on_table(p_table_name TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', p_table_name);
    EXECUTE format('
        CREATE POLICY "Allow access to own company data"
        ON public.%I
        FOR ALL
        USING (company_id = get_company_id())
        WITH CHECK (company_id = get_company_id());
    ', p_table_name);
END;
$$;

CALL enable_rls_on_table('companies');
CALL enable_rls_on_table('users');
CALL enable_rls_on_table('company_settings');
CALL enable_rls_on_table('suppliers');
CALL enable_rls_on_table('products');
CALL enable_rls_on_table('product_variants');
CALL enable_rls_on_table('customers');
CALL enable_rls_on_table('orders');
CALL enable_rls_on_table('order_line_items');
CALL enable_rls_on_table('purchase_orders');
CALL enable_rls_on_table('purchase_order_line_items');
CALL enable_rls_on_table('conversations');
CALL enable_rls_on_table('messages');
CALL enable_rls_on_table('inventory_ledger');
CALL enable_rls_on_table('integrations');
CALL enable_rls_on_table('webhook_events');
CALL enable_rls_on_table('discounts');
CALL enable_rls_on_table('customer_addresses');
CALL enable_rls_on_table('refunds');
CALL enable_rls_on_table('refund_line_items');


-- #### Transaction End ####
COMMIT;

-- Notify successful completion
SELECT 'Database migration to 2024-07-26 complete.' as status;
