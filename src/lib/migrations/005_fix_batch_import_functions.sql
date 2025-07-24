-- Migration to fix the syntax error in batch import functions.

-- Function to batch upsert product costs and reorder rules
CREATE OR REPLACE FUNCTION batch_upsert_costs(p_records jsonb, p_company_id UUID, p_user_id UUID)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT * FROM jsonb_to_recordset(p_records) AS x(
        sku TEXT,
        cost INT,
        supplier_name TEXT,
        reorder_point INT,
        reorder_quantity INT,
        lead_time_days INT
    )
    LOOP
        UPDATE product_variants
        SET
            cost = rec.cost,
            reorder_point = rec.reorder_point,
            reorder_quantity = rec.reorder_quantity,
            supplier_id = (SELECT id FROM suppliers WHERE name = rec.supplier_name AND company_id = p_company_id LIMIT 1),
            updated_at = now()
        WHERE
            sku = rec.sku AND company_id = p_company_id;
    END LOOP;
END;
$$;

-- Function to batch upsert suppliers
CREATE OR REPLACE FUNCTION batch_upsert_suppliers(p_records jsonb, p_company_id UUID, p_user_id UUID)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT * FROM jsonb_to_recordset(p_records) AS x(
        name TEXT,
        email TEXT,
        phone TEXT,
        default_lead_time_days INT,
        notes TEXT
    )
    LOOP
        INSERT INTO suppliers (company_id, name, email, phone, default_lead_time_days, notes)
        VALUES (p_company_id, rec.name, rec.email, rec.phone, rec.default_lead_time_days, rec.notes)
        ON CONFLICT (company_id, name) DO UPDATE SET
            email = EXCLUDED.email,
            phone = EXCLUDED.phone,
            default_lead_time_days = EXCLUDED.default_lead_time_days,
            notes = EXCLUDED.notes,
            updated_at = now();
    END LOOP;
END;
$$;

-- Function to batch import historical sales data
CREATE OR REPLACE FUNCTION batch_import_sales(p_records jsonb, p_company_id UUID, p_user_id UUID)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    rec RECORD;
    v_customer_id UUID;
    v_variant_id UUID;
    v_order_id UUID;
BEGIN
    FOR rec IN SELECT * FROM jsonb_to_recordset(p_records) AS x(
        order_date TEXT,
        sku TEXT,
        quantity INT,
        unit_price INT,
        cost_at_time INT,
        customer_email TEXT,
        order_id TEXT
    )
    LOOP
        -- Find the variant_id based on SKU
        SELECT id INTO v_variant_id FROM product_variants WHERE sku = rec.sku AND company_id = p_company_id LIMIT 1;

        -- If variant doesn't exist, skip this record
        IF v_variant_id IS NULL THEN
            CONTINUE;
        END IF;

        -- Find or create customer
        IF rec.customer_email IS NOT NULL THEN
            SELECT id INTO v_customer_id FROM customers WHERE email = rec.customer_email AND company_id = p_company_id;
            IF v_customer_id IS NULL THEN
                INSERT INTO customers (company_id, email, name) VALUES (p_company_id, rec.customer_email, rec.customer_email)
                RETURNING id INTO v_customer_id;
            END IF;
        ELSE
            v_customer_id := NULL;
        END IF;

        -- Create a simplified order record
        INSERT INTO orders (company_id, order_number, customer_id, total_amount, created_at, financial_status, fulfillment_status, source_platform)
        VALUES (p_company_id, coalesce(rec.order_id, 'IMPORT-' || to_char(now(), 'YYYYMMDDHH24MISS')), v_customer_id, rec.unit_price * rec.quantity, rec.order_date::timestamptz, 'paid', 'fulfilled', 'import')
        RETURNING id INTO v_order_id;
        
        -- Create the order line item
        INSERT INTO order_line_items (order_id, company_id, variant_id, sku, quantity, price, cost_at_time)
        VALUES (v_order_id, p_company_id, v_variant_id, rec.sku, rec.quantity, rec.unit_price, rec.cost_at_time);
    END LOOP;
END;
$$;
