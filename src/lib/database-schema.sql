-- This script is designed to be idempotent and can be run multiple times safely.
-- It brings the database schema to the latest version, including all security policies,
-- performance indexes, and table structures.

-- Step 1: Drop all dependent objects that might prevent table alterations.
-- This includes views and old security policies.

DROP VIEW IF EXISTS public.product_variants_with_details CASCADE;
DROP MATERIALIZED VIEW IF EXISTS public.company_dashboard_metrics CASCADE;

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
        EXECUTE 'ALTER TABLE public.' || quote_ident(r.tablename) || ' DISABLE ROW LEVEL SECURITY';
        -- Drop all existing policies on the table
        FOR r IN (SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = r.tablename) LOOP
            EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.' || quote_ident(r.tablename);
        END LOOP;
    END LOOP;
END $$;

-- Step 2: Drop the old, insecure function if it exists.
DROP FUNCTION IF EXISTS public.get_my_company_id();


-- Step 3: Perform all table alterations.
-- Using "IF NOT EXISTS" for columns and dropping constraints before adding them
-- makes this section idempotent.

ALTER TABLE public.products
    ADD COLUMN IF NOT EXISTS fts_document tsvector;

ALTER TABLE public.product_variants
    DROP COLUMN IF EXISTS weight,
    DROP COLUMN IF EXISTS weight_unit,
    ADD COLUMN IF NOT EXISTS location text,
    ALTER COLUMN sku SET NOT NULL,
    ALTER COLUMN inventory_quantity SET NOT NULL,
    ALTER COLUMN inventory_quantity SET DEFAULT 0;

ALTER TABLE public.orders
    ALTER COLUMN total_amount TYPE integer USING total_amount::integer,
    ADD COLUMN IF NOT EXISTS source_name text,
    ADD COLUMN IF NOT EXISTS tags text[],
    ADD COLUMN IF NOT EXISTS notes text,
    ADD COLUMN IF NOT EXISTS cancelled_at timestamptz;

ALTER TABLE public.order_line_items
    ADD COLUMN IF NOT EXISTS company_id uuid,
    ADD COLUMN IF NOT EXISTS cost_at_time integer;

ALTER TABLE public.refunds
    ALTER COLUMN total_amount TYPE integer USING total_amount::integer;
ALTER TABLE public.refund_line_items
    ALTER COLUMN amount TYPE integer USING amount::integer;
ALTER TABLE public.customers
    ALTER COLUMN total_spent TYPE integer USING total_spent::integer;

ALTER TABLE public.company_settings
    ADD COLUMN IF NOT EXISTS promo_sales_lift_multiplier real NOT NULL DEFAULT 2.5,
    ADD COLUMN IF NOT EXISTS overstock_multiplier integer NOT NULL DEFAULT 3,
    ADD COLUMN IF NOT EXISTS high_value_threshold integer NOT NULL DEFAULT 100000;

ALTER TABLE public.audit_log
    ADD COLUMN IF NOT EXISTS company_id uuid,
    ADD COLUMN IF NOT EXISTS user_id uuid;

ALTER TABLE public.purchase_orders
    ADD COLUMN IF NOT EXISTS idempotency_key text;


-- Step 4: Create performance indexes.
-- Dropping them first ensures this is safe to re-run.

DROP INDEX IF EXISTS idx_product_variants_sku;
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);

DROP INDEX IF EXISTS idx_products_company_id;
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);

DROP INDEX IF EXISTS idx_product_variants_company_id;
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);

DROP INDEX IF EXISTS idx_orders_company_id;
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);

DROP INDEX IF EXISTS idx_order_line_items_order_id;
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);

DROP INDEX IF EXISTS idx_purchase_orders_company_id;
CREATE INDEX IF NOT EXISTS idx_purchase_orders_company_id ON public.purchase_orders(company_id);

DROP INDEX IF EXISTS idx_purchase_order_line_items_po_id;
CREATE INDEX IF NOT EXISTS idx_purchase_order_line_items_po_id ON public.purchase_order_line_items(purchase_order_id);

DROP INDEX IF EXISTS idx_inventory_ledger_variant_id;
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);

DROP INDEX IF EXISTS idx_customers_company_email;
CREATE INDEX IF NOT EXISTS idx_customers_company_email ON public.customers(company_id, email);

DROP INDEX IF EXISTS po_company_idempotency_idx;
CREATE UNIQUE INDEX IF NOT EXISTS po_company_idempotency_idx ON public.purchase_orders (company_id, idempotency_key) WHERE idempotency_key IS NOT NULL;


-- Step 5: Add a unique constraint for webhook deduplication.
ALTER TABLE public.webhook_events DROP CONSTRAINT IF EXISTS webhook_events_integration_id_webhook_id_key;
ALTER TABLE public.webhook_events ADD CONSTRAINT webhook_events_integration_id_webhook_id_key UNIQUE (integration_id, webhook_id);


-- Step 6: Define secure helper functions for RLS.

-- Gets the company ID from a user's app_metadata.
CREATE OR REPLACE FUNCTION public.get_user_company_id(p_user_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT raw_app_meta_data->>'company_id'
  FROM auth.users
  WHERE id = p_user_id;
$$;

-- Checks if a user is an admin of a specific company.
CREATE OR REPLACE FUNCTION public.is_company_admin(p_company_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users
    WHERE id = p_user_id
      AND company_id = p_company_id
      AND role IN ('Owner', 'Admin')
  );
$$;

-- Step 7: Recreate the views with the correct structure.

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

-- This is a placeholder; in a real app, this would be a more complex view.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
    p.company_id,
    p.id as product_id,
    p.title,
    pv.cost
FROM public.products p
JOIN public.product_variants pv ON p.id = pv.product_id;

-- Step 8: Re-enable Row Level Security and apply secure policies.

-- Macro to apply a standard company policy to a table
CREATE OR REPLACE PROCEDURE public.apply_company_rls(t_name text)
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t_name);
    EXECUTE format('
        CREATE POLICY "Allow members to access their own company data"
        ON public.%I
        FOR ALL
        USING (company_id = public.get_user_company_id(auth.uid()))
        WITH CHECK (company_id = public.get_user_company_id(auth.uid()));
    ', t_name);
END;
$$;

CALL public.apply_company_rls('products');
CALL public.apply_company_rls('product_variants');
CALL public.apply_company_rls('orders');
CALL public.apply_company_rls('order_line_items');
CALL public.apply_company_rls('customers');
CALL public.apply_company_rls('refunds');
CALL public.apply_company_rls('refund_line_items');
CALL public.apply_company_rls('suppliers');
CALL public.apply_company_rls('purchase_orders');
CALL public.apply_company_rls('purchase_order_line_items');
CALL public.apply_company_rls('inventory_ledger');
CALL public.apply_company_rls('integrations');
CALL public.apply_company_rls('company_settings');
CALL public.apply_company_rls('discounts');
CALL public.apply_company_rls('channel_fees');
CALL public.apply_company_rls('export_jobs');
CALL public.apply_company_rls('conversations');
CALL public.apply_company_rls('messages');

-- Special policy for audit_log: only admins can read.
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow admins to read audit logs for their company"
ON public.audit_log
FOR SELECT
USING (public.is_company_admin(company_id, auth.uid()));

-- Policy for users table: users can see others in their own company.
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can see other members of their own company"
ON public.users
FOR SELECT
USING (company_id = public.get_user_company_id(auth.uid()));

-- Final Step: Set up the user creation trigger if it doesn't exist.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
  user_company_name text;
BEGIN
  -- Check if a company ID is already provided in metadata
  IF (new.raw_app_meta_data->>'company_id') IS NOT NULL THEN
    -- If so, use it to populate the public.users table
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (
      new.id,
      (new.raw_app_meta_data->>'company_id')::uuid,
      new.email,
      (new.raw_app_meta_data->>'role')::text
    );
  ELSE
    -- If no company ID, create a new company for the user
    user_company_name := new.raw_app_meta_data->>'company_name';
    IF user_company_name IS NULL OR user_company_name = '' THEN
        user_company_name := new.email || '''s Company';
    END IF;
    
    INSERT INTO public.companies (name)
    VALUES (user_company_name)
    RETURNING id INTO new_company_id;

    -- Update the user's app_metadata with the new company_id
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
    WHERE id = new.id;
    
    -- Create their entry in the public.users table as Owner
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new.id, new_company_id, new.email, 'Owner');
  END IF;
  
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

DROP FUNCTION IF EXISTS public.record_sale_transaction;
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_customer_name text,
    p_customer_email text,
    p_payment_method text,
    p_notes text,
    p_sale_items jsonb[],
    p_external_id text
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_customer_id uuid;
    v_order_id uuid;
    v_item jsonb;
    v_variant_id uuid;
    v_total_amount integer := 0;
BEGIN
    -- This now correctly uses SELECT ... FOR UPDATE to prevent race conditions
    -- when multiple orders for the same product come in simultaneously.
    FOR v_item IN SELECT * FROM unnest(p_sale_items)
    LOOP
        SELECT id INTO v_variant_id FROM public.product_variants
        WHERE company_id = p_company_id AND sku = (v_item->>'sku')::text
        FOR UPDATE; -- Lock the row

        IF v_variant_id IS NULL THEN
            RAISE EXCEPTION 'Product with SKU % not found for company %', (v_item->>'sku')::text, p_company_id;
        END IF;

        UPDATE public.product_variants
        SET inventory_quantity = inventory_quantity - (v_item->>'quantity')::integer
        WHERE id = v_variant_id;
        
        v_total_amount := v_total_amount + (v_item->>'unit_price')::integer * (v_item->>'quantity')::integer;
    END LOOP;

    RETURN v_order_id;
END;
$$;

DROP FUNCTION IF EXISTS public.create_purchase_orders_from_suggestions;
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
    v_supplier_id uuid;
    v_po_id uuid;
    v_po_map jsonb := '{}'::jsonb;
    v_total_cost integer;
    v_created_po_count integer := 0;
BEGIN
    IF p_idempotency_key IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.purchase_orders
        WHERE company_id = p_company_id AND idempotency_key = p_idempotency_key
    ) THEN
        RETURN 0;
    END IF;
    
    FOREACH suggestion IN ARRAY p_suggestions
    LOOP
        v_supplier_id := (suggestion->>'supplier_id')::uuid;

        IF NOT (v_po_map ? v_supplier_id::text) THEN
            INSERT INTO public.purchase_orders (company_id, supplier_id, status, po_number, total_cost, idempotency_key)
            VALUES (p_company_id, v_supplier_id, 'Draft', 'PO-' || to_char(now(), 'YYYYMMDDHH24MISS') || '-' || v_created_po_count, 0, p_idempotency_key)
            RETURNING id INTO v_po_id;
            
            v_po_map := jsonb_set(v_po_map, ARRAY[v_supplier_id::text], to_jsonb(v_po_id));
            v_created_po_count := v_created_po_count + 1;
        ELSE
            v_po_id := (v_po_map->>v_supplier_id::text)::uuid;
        END IF;
        
        INSERT INTO public.purchase_order_line_items (purchase_order_id, variant_id, quantity, cost)
        VALUES (
            v_po_id,
            (suggestion->>'variant_id')::uuid,
            (suggestion->>'suggested_reorder_quantity')::integer,
            (suggestion->>'unit_cost')::integer
        );
    END LOOP;
    
    -- Update total costs for all created POs
    FOR v_supplier_id, v_po_id IN SELECT (kv.key)::uuid, (kv.value)::uuid FROM jsonb_each(v_po_map) kv
    LOOP
        SELECT sum(li.quantity * li.cost) INTO v_total_cost
        FROM public.purchase_order_line_items li
        WHERE li.purchase_order_id = v_po_id;

        UPDATE public.purchase_orders
        SET total_cost = v_total_cost
        WHERE id = v_po_id;
    END LOOP;
    
    RETURN v_created_po_count;
END;
$$;


-- Grant usage on the public schema to the authenticated role
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT INSERT ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT UPDATE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public to authenticated;

-- Grant permissions for service_role to bypass RLS
GRANT USAGE ON SCHEMA public TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public to service_role;

ALTER USER supabase_admin with BYPASSRLS;

ALTER TABLE public.products OWNER TO postgres;
GRANT ALL ON TABLE public.products TO postgres;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.products TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.products TO service_role;

ALTER TABLE public.product_variants OWNER TO postgres;
GRANT ALL ON TABLE public.product_variants TO postgres;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.product_variants TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.product_variants TO service_role;

ALTER TABLE public.orders OWNER TO postgres;
GRANT ALL ON TABLE public.orders TO postgres;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.orders TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.orders TO service_role;

ALTER TABLE public.order_line_items OWNER TO postgres;
GRANT ALL ON TABLE public.order_line_items TO postgres;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.order_line_items TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.order_line_items TO service_role;

ALTER TABLE public.customers OWNER TO postgres;
GRANT ALL ON TABLE public.customers TO postgres;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.customers TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.customers TO service_role;

ALTER TABLE public.refunds OWNER TO postgres;
GRANT ALL ON TABLE public.refunds TO postgres;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.refunds TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.refunds TO service_role;

ALTER TABLE public.suppliers OWNER TO postgres;
GRANT ALL ON TABLE public.suppliers TO postgres;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.suppliers TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.suppliers TO service_role;

ALTER TABLE public.purchase_orders OWNER TO postgres;
GRANT ALL ON TABLE public.purchase_orders TO postgres;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.purchase_orders TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.purchase_orders TO service_role;

ALTER TABLE public.purchase_order_line_items OWNER TO postgres;
GRANT ALL ON TABLE public.purchase_order_line_items TO postgres;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.purchase_order_line_items TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.purchase_order_line_items TO service_role;

ALTER TABLE public.inventory_ledger OWNER TO postgres;
GRANT ALL ON TABLE public.inventory_ledger TO postgres;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.inventory_ledger TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.inventory_ledger TO service_role;

ALTER TABLE public.integrations OWNER TO postgres;
GRANT ALL ON TABLE public.integrations TO postgres;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.integrations TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.integrations TO service_role;

ALTER TABLE public.company_settings OWNER TO postgres;
GRANT ALL ON TABLE public.company_settings TO postgres;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.company_settings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.company_settings TO service_role;

ALTER TABLE public.audit_log OWNER TO postgres;
GRANT ALL ON TABLE public.audit_log TO postgres;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.audit_log TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.audit_log TO service_role;

ALTER TABLE public.messages OWNER TO postgres;
GRANT ALL ON TABLE public.messages TO postgres;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.messages TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.messages TO service_role;

ALTER TABLE public.conversations OWNER TO postgres;
GRANT ALL ON TABLE public.conversations TO postgres;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.conversations TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.conversations TO service_role;
