-- Table to track the status and results of data import jobs
CREATE TABLE IF NOT EXISTS public.imports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES auth.users(id),
    import_type text NOT NULL,
    file_name text NOT NULL,
    total_rows integer,
    processed_rows integer,
    failed_rows integer,
    status text NOT NULL DEFAULT 'pending', -- pending, processing, completed, completed_with_errors, failed
    errors jsonb,
    summary jsonb,
    created_at timestamptz DEFAULT now(),
    completed_at timestamptz
);

-- Indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_imports_company_id ON public.imports(company_id);
CREATE INDEX IF NOT EXISTS idx_imports_status ON public.imports(status);


-- Function to batch upsert product costs and reorder rules
CREATE OR REPLACE FUNCTION public.batch_upsert_costs(
    p_records jsonb[],
    p_company_id uuid,
    p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    rec jsonb;
    v_supplier_id uuid;
BEGIN
    FOREACH rec IN ARRAY p_records
    LOOP
        -- Find or create the supplier
        IF rec ->> 'supplier_name' IS NOT NULL THEN
            SELECT id INTO v_supplier_id
            FROM public.suppliers
            WHERE company_id = p_company_id AND name = rec ->> 'supplier_name';

            IF v_supplier_id IS NULL THEN
                INSERT INTO public.suppliers (company_id, name)
                VALUES (p_company_id, rec ->> 'supplier_name')
                RETURNING id INTO v_supplier_id;
            END IF;
        END IF;

        -- Upsert the product variant cost and reorder info
        UPDATE public.product_variants
        SET
            cost = (rec ->> 'cost')::integer,
            reorder_point = (rec ->> 'reorder_point')::integer,
            reorder_quantity = (rec ->> 'reorder_quantity')::integer,
            supplier_id = v_supplier_id,
            updated_at = now()
        WHERE
            company_id = p_company_id
            AND sku = rec ->> 'sku';
    END LOOP;
END;
$$;


-- Function to batch upsert suppliers
CREATE OR REPLACE FUNCTION public.batch_upsert_suppliers(
    p_records jsonb[],
    p_company_id uuid,
    p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.suppliers (company_id, name, email, phone, default_lead_time_days, notes)
    SELECT
        p_company_id,
        r ->> 'name',
        r ->> 'email',
        r ->> 'phone',
        (r ->> 'default_lead_time_days')::integer,
        r ->> 'notes'
    FROM jsonb_array_elements(array_to_json(p_records)::jsonb) r
    ON CONFLICT (company_id, name) DO UPDATE SET
        email = EXCLUDED.email,
        phone = EXCLUDED.phone,
        default_lead_time_days = EXCLUDED.default_lead_time_days,
        notes = EXCLUDED.notes,
        updated_at = now();
END;
$$;

-- Function to batch import historical sales data
CREATE OR REPLACE FUNCTION public.batch_import_sales(
    p_records jsonb[],
    p_company_id uuid,
    p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_order RECORD;
    v_variant RECORD;
    v_customer_id uuid;
    v_order_id uuid;
BEGIN
    FOREACH v_order IN SELECT * FROM jsonb_to_recordset(array_to_json(p_records)::jsonb) AS x(
        order_date timestamptz,
        sku text,
        quantity integer,
        unit_price integer,
        cost_at_time integer,
        customer_email text,
        order_id text
    )
    LOOP
        -- Find variant
        SELECT id, product_id INTO v_variant
        FROM public.product_variants
        WHERE company_id = p_company_id AND sku = v_order.sku;

        -- Find or create customer
        IF v_order.customer_email IS NOT NULL THEN
            SELECT id INTO v_customer_id FROM public.customers
            WHERE company_id = p_company_id AND email = v_order.customer_email;

            IF v_customer_id IS NULL THEN
                INSERT INTO public.customers (company_id, email, customer_name)
                VALUES (p_company_id, v_order.customer_email, v_order.customer_email)
                RETURNING id INTO v_customer_id;
            END IF;
        END IF;

        -- Find or create order
        IF v_order.order_id IS NOT NULL THEN
            SELECT id INTO v_order_id FROM public.orders
            WHERE company_id = p_company_id AND external_order_id = v_order.order_id;
        END IF;
        
        IF v_order_id IS NULL THEN
            INSERT INTO public.orders (company_id, order_number, customer_id, total_amount, subtotal, source_platform, created_at, external_order_id)
            VALUES (
                p_company_id,
                'HISTORICAL-' || v_order.order_id,
                v_customer_id,
                v_order.quantity * v_order.unit_price,
                v_order.quantity * v_order.unit_price,
                'historical_import',
                v_order.order_date,
                v_order.order_id
            ) RETURNING id INTO v_order_id;
        END IF;

        -- Insert line item
        IF v_variant.id IS NOT NULL AND v_order_id IS NOT NULL THEN
             INSERT INTO public.order_line_items (company_id, order_id, variant_id, sku, product_name, quantity, price, cost_at_time)
             SELECT p_company_id, v_order_id, v_variant.id, v_order.sku, p.title, v_order.quantity, v_order.unit_price, v_order.cost_at_time
             FROM public.products p WHERE p.id = v_variant.product_id;
        END IF;
    END LOOP;
END;
$$;
