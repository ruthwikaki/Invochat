--
-- Universal ARVO Migration Script (from initial schema to latest)
-- This script is designed to be idempotent and can be run on databases
-- that have the original `database-schema.sql` or have had partial
-- migrations applied.
--

-- DO $$
-- BEGIN
--   -- This block is commented out as it caused recurring dependency issues.
--   -- RLS policies will be dropped and recreated individually.
-- END;
-- $$;


-- Step 1: Drop dependent views before altering tables.
-- This is critical to avoid "cannot drop columns from view" errors.
DROP VIEW IF EXISTS public.orders_view;
DROP VIEW IF EXISTS public.customers_view;


-- Step 2: Alter tables to fix inconsistencies and add new columns.

-- Modify 'orders' table
ALTER TABLE "public"."orders" 
  DROP COLUMN IF EXISTS "status",
  ALTER COLUMN "subtotal" SET DEFAULT 0,
  ALTER COLUMN "total_shipping" SET DEFAULT 0,
  ALTER COLUMN "total_discounts" SET DEFAULT 0,
  ALTER COLUMN "total_tax" SET DEFAULT 0;

-- Modify 'product_variants' table
ALTER TABLE "public"."product_variants" 
  ADD COLUMN IF NOT EXISTS "location" TEXT;

-- Modify 'company_settings' table
ALTER TABLE public.company_settings 
  ADD COLUMN IF NOT EXISTS promo_sales_lift_multiplier REAL NOT NULL DEFAULT 2.5,
  ADD COLUMN IF NOT EXISTS overstock_multiplier INTEGER NOT NULL DEFAULT 3,
  ADD COLUMN IF NOT EXISTS high_value_threshold INTEGER NOT NULL DEFAULT 1000,
  ALTER COLUMN high_value_threshold SET DEFAULT 100000; -- Correcting the default for future inserts.

-- Modify 'users' table
ALTER TABLE public.users 
  ALTER COLUMN "role" SET DEFAULT 'member'::text;

-- Modify 'order_line_items' table
-- Backfill null SKUs to prevent the NOT NULL constraint from failing.
UPDATE public.order_line_items SET sku = 'UNKNOWN' WHERE sku IS NULL;
ALTER TABLE public.order_line_items
  ALTER COLUMN sku SET NOT NULL;

-- Modify 'purchase_orders' table
ALTER TABLE public.purchase_orders 
  ADD COLUMN IF NOT EXISTS idempotency_key UUID;
  

-- Step 3: Drop potentially outdated functions and procedures that will be recreated.
-- This prevents errors when changing function signatures.

DROP FUNCTION IF EXISTS public.get_company_id();
DROP PROCEDURE IF EXISTS enable_rls_on_table(text);
DROP FUNCTION IF EXISTS public.record_sale_transaction(uuid, uuid, text, text, text, text, jsonb);


-- Step 4: Recreate helper functions and procedures with corrected logic.

CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT current_setting('app.current_company_id')::uuid;
$$;
COMMENT ON FUNCTION public.get_company_id() IS 'A security-definer helper to reliably get the company_id from the session.';


CREATE OR REPLACE PROCEDURE public.enable_rls_on_table(p_table_name TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE 'DROP POLICY IF EXISTS "Allow all access to own company data" ON public.' || quote_ident(p_table_name);
    EXECUTE 'ALTER TABLE public.' || quote_ident(p_table_name) || ' ENABLE ROW LEVEL SECURITY';
    EXECUTE 'ALTER TABLE public.' || quote_ident(p_table_name) || ' FORCE ROW LEVEL SECURITY';
    EXECUTE 'CREATE POLICY "Allow all access to own company data" ON public.' || quote_ident(p_table_name)
        || ' FOR ALL USING (company_id = get_company_id())';
END;
$$;
COMMENT ON PROCEDURE public.enable_rls_on_table(text) IS 'A helper procedure to apply a standard RLS policy to a table.';


CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_customer_name text,
    p_customer_email text,
    p_payment_method text,
    p_notes text,
    p_sale_items jsonb,
    p_external_id text
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_customer_id uuid;
    v_order_id uuid;
    v_variant_id uuid;
    v_sale_item record;
    v_current_quantity integer;
BEGIN
    -- Find or create the customer
    SELECT id INTO v_customer_id
    FROM customers
    WHERE email = p_customer_email AND company_id = p_company_id;

    IF v_customer_id IS NULL THEN
        INSERT INTO customers (company_id, customer_name, email)
        VALUES (p_company_id, p_customer_name, p_customer_email)
        RETURNING id INTO v_customer_id;
    END IF;

    -- Create the order
    INSERT INTO orders (company_id, customer_id, total_amount, source_name, notes, external_order_id)
    VALUES (p_company_id, v_customer_id, 0, p_payment_method, p_notes, p_external_id)
    RETURNING id INTO v_order_id;

    -- Process each line item
    FOR v_sale_item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, product_name text, quantity integer, unit_price integer, cost_at_time integer)
    LOOP
        -- Get the variant ID for the SKU
        SELECT id INTO v_variant_id
        FROM product_variants
        WHERE sku = v_sale_item.sku AND company_id = p_company_id;

        IF v_variant_id IS NULL THEN
            RAISE EXCEPTION 'Product with SKU % not found', v_sale_item.sku;
        END IF;

        -- **Lock the variant row to prevent race conditions**
        SELECT inventory_quantity INTO v_current_quantity
        FROM product_variants
        WHERE id = v_variant_id
        FOR UPDATE;

        -- **Prevent stock from going negative**
        IF v_current_quantity < v_sale_item.quantity THEN
            RAISE EXCEPTION 'Insufficient stock for SKU %: Tried to sell %, but only % available.', v_sale_item.sku, v_sale_item.quantity, v_current_quantity;
        END IF;

        -- Update inventory
        UPDATE product_variants
        SET inventory_quantity = inventory_quantity - v_sale_item.quantity
        WHERE id = v_variant_id;

        -- Create inventory ledger entry
        INSERT INTO inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id)
        VALUES (p_company_id, v_variant_id, 'sale', -v_sale_item.quantity, v_current_quantity - v_sale_item.quantity, v_order_id);

        -- Create order line item
        INSERT INTO order_line_items (order_id, variant_id, company_id, product_name, sku, quantity, price, cost_at_time)
        VALUES (v_order_id, v_variant_id, p_company_id, v_sale_item.product_name, v_sale_item.sku, v_sale_item.quantity, v_sale_item.unit_price, v_sale_item.cost_at_time);
    END LOOP;

    -- Update the order total
    UPDATE orders
    SET total_amount = (
        SELECT COALESCE(SUM(quantity * price), 0)
        FROM order_line_items
        WHERE order_id = v_order_id
    )
    WHERE id = v_order_id;
    
    RETURN v_order_id;
END;
$$;


-- Step 5: Recreate views with correct dependencies and structure.

CREATE OR REPLACE VIEW public.customers_view AS
SELECT 
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    c.total_orders, -- Use the pre-calculated value from the customers table
    c.total_spent
FROM 
    public.customers c;

CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.id,
    o.company_id,
    o.order_number,
    o.customer_id,
    c.email AS customer_email,
    o.created_at,
    o.total_amount,
    o.fulfillment_status,
    o.source_platform
FROM
    public.orders o
LEFT JOIN
    public.customers c ON o.customer_id = c.id;


-- Step 6: Apply indexes for performance.

CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_variants_sku ON public.product_variants(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_ledger_variant_date ON public.inventory_ledger(company_id, variant_id, created_at DESC);


-- Step 7: Re-apply RLS policies to all tables.
DO $$
DECLARE
    t_name TEXT;
BEGIN
    FOR t_name IN 
        SELECT tablename FROM pg_tables WHERE schemaname = 'public'
    LOOP
        -- Drop old policies to be safe
        EXECUTE 'DROP POLICY IF EXISTS "Allow all access to own company data" ON public.' || quote_ident(t_name);
        
        -- Enable RLS and apply the new, stricter policy
        CALL public.enable_rls_on_table(t_name);
    END LOOP;
END;
$$;


-- Final logging
SELECT 'Migration script completed successfully.';
