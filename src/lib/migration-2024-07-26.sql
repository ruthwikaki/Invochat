
-- Drop dependent views and functions first in the correct order.
DROP VIEW IF EXISTS public.orders_view;
DROP VIEW IF EXISTS public.product_variants_with_details;

-- Now drop the function
DROP FUNCTION IF EXISTS public.get_company_id();

-- Recreate the function to be STABLE for performance
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;


-- Recreate product_variants_with_details view
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    pv.company_id,
    p.title AS product_title,
    p.status as product_status,
    p.image_url,
    pv.sku,
    pv.title AS title,
    pv.option1_name,
    pv.option1_value,
    pv.option2_name,
    pv.option2_value,
    pv.option3_name,
    pv.option3_value,
    pv.barcode,
    pv.price,
    pv.compare_at_price,
    pv.cost,
    pv.inventory_quantity,
    pv.location,
    pv.external_variant_id,
    pv.created_at,
    pv.updated_at
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id AND pv.company_id = p.company_id;


-- Recreate orders_view
CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.id,
    o.company_id,
    o.order_number,
    o.external_order_id,
    o.customer_id,
    c.email AS customer_email,
    o.financial_status,
    o.fulfillment_status,
    o.currency,
    o.subtotal,
    o.total_tax,
    o.total_shipping,
    o.total_discounts,
    o.total_amount,
    o.source_platform,
    o.created_at,
    o.updated_at
FROM
    public.orders o
LEFT JOIN
    public.customers c ON o.customer_id = c.id;

-- Drop constraints if they exist to make the script idempotent
ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS product_variants_company_id_fkey;
ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS product_variants_product_id_fkey;
ALTER TABLE public.inventory_ledger DROP CONSTRAINT IF EXISTS inventory_ledger_variant_id_fkey;
ALTER TABLE public.order_line_items DROP CONSTRAINT IF EXISTS order_line_items_variant_id_fkey;
ALTER TABLE public.purchase_order_line_items DROP CONSTRAINT IF EXISTS purchase_order_line_items_variant_id_fkey;

-- Add all necessary constraints
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;
ALTER TABLE public.inventory_ledger ADD CONSTRAINT inventory_ledger_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE CASCADE;
ALTER TABLE public.order_line_items ADD CONSTRAINT order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;
ALTER TABLE public.purchase_order_line_items ADD CONSTRAINT purchase_order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE CASCADE;

-- Drop the old trigger and function if it exists to handle re-running the script
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Recreate the user creation function
CREATE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    company_id_from_meta uuid;
    new_company_id uuid;
BEGIN
    -- Check if company_id is provided in metadata (for invites)
    company_id_from_meta := (new.raw_app_meta_data->>'company_id')::uuid;

    IF company_id_from_meta IS NOT NULL THEN
        -- If invited, use the existing company ID
        new_company_id := company_id_from_meta;
        -- Insert into public.users with 'Member' role
        INSERT INTO public.users (id, company_id, email, role)
        VALUES (new.id, new_company_id, new.email, 'Member');
    ELSE
        -- If signing up directly, create a new company
        INSERT INTO public.companies (name)
        VALUES (new.raw_app_meta_data->>'company_name')
        RETURNING id INTO new_company_id;
        
        -- Insert into public.users with 'Owner' role
        INSERT INTO public.users (id, company_id, email, role)
        VALUES (new.id, new_company_id, new.email, 'Owner');
    END IF;

    -- Update the user's app_metadata with the determined company_id and a default role
    UPDATE auth.users
    SET raw_app_meta_data = jsonb_set(
        jsonb_set(raw_app_meta_data, '{company_id}', to_jsonb(new_company_id)),
        '{role}', to_jsonb(COALESCE(company_id_from_meta, new_company_id, 'Owner'::text))
    )
    WHERE id = new.id;
    
    RETURN new;
END;
$$;

-- Recreate the trigger
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();


-- Drop all RLS policies on public tables before recreating them
DO $$
DECLARE
    table_record RECORD;
BEGIN
    FOR table_record IN
        SELECT tablename FROM pg_tables WHERE schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS "Allow all access to own company data" ON %1$I.%2$I;', 'public', table_record.tablename);
    END LOOP;
END;
$$ LANGUAGE plpgsql;


-- Function to enable RLS on all public tables
CREATE OR REPLACE FUNCTION enable_rls_for_all_tables(schema_name TEXT)
RETURNS VOID AS $$
DECLARE
    table_record RECORD;
    policy_sql TEXT;
BEGIN
    FOR table_record IN
        SELECT tablename FROM pg_tables WHERE schemaname = schema_name
    LOOP
        EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY;', schema_name, table_record.tablename);

        IF table_record.tablename = 'companies' THEN
            policy_sql := format(
                'CREATE POLICY "Allow all access to own company data" ON %1$I.%2$I FOR ALL USING (id = public.get_company_id());',
                schema_name, table_record.tablename
            );
        ELSIF table_record.tablename = 'webhook_events' THEN
            policy_sql := format(
                'CREATE POLICY "Allow all access to own company data" ON %1$I.%2$I FOR ALL USING ((SELECT company_id FROM public.integrations WHERE id = %2$I.integration_id) = public.get_company_id());',
                schema_name, table_record.tablename
            );
        ELSIF table_record.tablename = 'customer_addresses' THEN
             policy_sql := format(
                'CREATE POLICY "Allow all access to own company data" ON %1$I.%2$I FOR ALL USING ((SELECT company_id FROM public.customers WHERE id = %2$I.customer_id) = public.get_company_id());',
                schema_name, table_record.tablename
            );
        ELSE
             policy_sql := format(
                'CREATE POLICY "Allow all access to own company data" ON %1$I.%2$I FOR ALL USING (company_id = public.get_company_id());',
                schema_name, table_record.tablename
            );
        END IF;

        EXECUTE policy_sql;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Run the function to apply RLS
SELECT enable_rls_for_all_tables('public');

-- Drop the function after use
DROP FUNCTION IF EXISTS enable_rls_for_all_tables(text);


-- Add new 'idempotency_key' column to purchase_orders table
ALTER TABLE public.purchase_orders
ADD COLUMN IF NOT EXISTS idempotency_key UUID;

-- Update record_sale_transaction function for better concurrency and accuracy
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
RETURNS uuid AS $$
DECLARE
    v_customer_id uuid;
    v_order_id uuid;
    v_subtotal int := 0;
    v_total_amount int := 0;
    item jsonb;
    v_variant_id uuid;
    v_quantity int;
    v_price int;
    v_cost_at_time int;
    current_stock int;
BEGIN
    -- Find or create the customer
    SELECT id INTO v_customer_id FROM customers WHERE email = p_customer_email AND company_id = p_company_id;
    IF NOT FOUND THEN
        INSERT INTO customers (company_id, customer_name, email)
        VALUES (p_company_id, p_customer_name, p_customer_email)
        RETURNING id INTO v_customer_id;
    END IF;

    -- Create the order
    INSERT INTO orders (company_id, order_number, customer_id, total_amount, subtotal, source_platform, external_order_id, financial_status, fulfillment_status)
    VALUES (p_company_id, 'SALE-' || substr(uuid_generate_v4()::text, 1, 8), v_customer_id, 0, 0, 'manual', p_external_id, 'paid', 'fulfilled')
    RETURNING id INTO v_order_id;
    
    -- Process line items
    FOREACH item IN ARRAY p_sale_items
    LOOP
        SELECT id, cost INTO v_variant_id, v_cost_at_time
        FROM product_variants
        WHERE sku = item->>'sku' AND company_id = p_company_id;
        
        v_quantity := (item->>'quantity')::int;
        v_price := (item->>'unit_price')::int;
        v_subtotal := v_subtotal + (v_quantity * v_price);

        INSERT INTO order_line_items (order_id, company_id, variant_id, product_name, sku, quantity, price, cost_at_time)
        VALUES (v_order_id, p_company_id, v_variant_id, item->>'product_name', item->>'sku', v_quantity, v_price, COALESCE((item->>'cost_at_time')::int, v_cost_at_time));

        -- Lock the variant row to prevent race conditions
        SELECT inventory_quantity INTO current_stock FROM product_variants WHERE id = v_variant_id FOR UPDATE;

        -- Update inventory and create ledger entry
        UPDATE product_variants SET inventory_quantity = inventory_quantity - v_quantity WHERE id = v_variant_id;
        
        INSERT INTO inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
        VALUES (p_company_id, v_variant_id, 'sale', -v_quantity, current_stock - v_quantity, v_order_id, 'Order ' || 'SALE-' || substr(v_order_id::text, 1, 8));
    END LOOP;

    v_total_amount := v_subtotal;
    UPDATE orders SET total_amount = v_total_amount, subtotal = v_subtotal WHERE id = v_order_id;
    
    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql;


-- Update the function to create purchase orders
CREATE OR REPLACE FUNCTION public.create_purchase_orders_from_suggestions(
    p_company_id uuid,
    p_user_id uuid,
    p_suggestions jsonb,
    p_idempotency_key uuid DEFAULT NULL
)
RETURNS int AS $$
DECLARE
    suggestion jsonb;
    v_supplier_id uuid;
    v_po_id uuid;
    v_po_map jsonb := '{}'::jsonb;
    v_total_cost int;
    v_po_count int := 0;
    v_po_number_prefix text;
BEGIN
    -- Check for idempotency
    IF p_idempotency_key IS NOT NULL THEN
        SELECT COUNT(*) INTO v_po_count FROM purchase_orders WHERE idempotency_key = p_idempotency_key AND company_id = p_company_id;
        IF v_po_count > 0 THEN
            RETURN v_po_count;
        END IF;
    END IF;

    SELECT TO_CHAR(CURRENT_DATE, 'YYYYMMDD') INTO v_po_number_prefix;

    -- Group suggestions by supplier
    FOR suggestion IN SELECT * FROM jsonb_array_elements(p_suggestions)
    LOOP
        v_supplier_id := (suggestion->>'supplier_id')::uuid;

        -- Create a new PO if one doesn't exist for this supplier
        IF NOT (v_po_map ? v_supplier_id::text) THEN
            INSERT INTO purchase_orders (company_id, supplier_id, status, po_number, total_cost, idempotency_key)
            VALUES (p_company_id, v_supplier_id, 'Ordered', v_po_number_prefix || '-' || LPAD((nextval('purchase_orders_po_number_seq'))::text, 4, '0'), 0, p_idempotency_key)
            RETURNING id INTO v_po_id;
            
            v_po_map := jsonb_set(v_po_map, ARRAY[v_supplier_id::text], to_jsonb(v_po_id));
            v_po_count := v_po_count + 1;
        END IF;

        v_po_id := (v_po_map->>v_supplier_id::text)::uuid;

        -- Add line item to the PO
        INSERT INTO purchase_order_line_items (purchase_order_id, company_id, variant_id, quantity, cost)
        VALUES (v_po_id, p_company_id, (suggestion->>'variant_id')::uuid, (suggestion->>'suggested_reorder_quantity')::int, (suggestion->>'unit_cost')::int);
    END LOOP;
    
    -- Update total costs for all created POs
    FOR v_supplier_id, v_po_id IN SELECT (key)::uuid, (value)::uuid FROM jsonb_each(v_po_map)
    LOOP
        SELECT SUM(quantity * cost) INTO v_total_cost
        FROM purchase_order_line_items
        WHERE purchase_order_id = v_po_id;

        UPDATE purchase_orders SET total_cost = v_total_cost WHERE id = v_po_id;
    END LOOP;

    RETURN v_po_count;
END;
$$ LANGUAGE plpgsql;

-- Final cleanup of old, unused functions
DROP FUNCTION IF EXISTS public.record_sale(uuid,text,text,text,text,jsonb[],text);
DROP FUNCTION IF EXISTS public.update_inventory(uuid,int,text,uuid,text);
```