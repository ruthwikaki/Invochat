export const SETUP_SQL_SCRIPT = `-- InvoChat Database Setup Script
-- This script is idempotent and can be safely re-run on an existing database.
-- It works in both standard PostgreSQL and Supabase environments.

-- ========= Part 1: Environment Detection and Extension Setup =========

-- Detect and setup Supabase-specific features
DO $$
DECLARE
    is_supabase BOOLEAN := FALSE;
BEGIN
    -- Check if we're in a Supabase environment by looking for auth schema
    IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'auth') THEN
        is_supabase := TRUE;
        RAISE NOTICE 'Detected Supabase environment';
    END IF;

    -- Only setup pgsodium and vault in Supabase environments
    IF is_supabase THEN
        -- Setup pgsodium extension and permissions
        BEGIN
            -- Create pgsodium schema if needed
            CREATE SCHEMA IF NOT EXISTS pgsodium;
            
            -- Install extension
            CREATE EXTENSION IF NOT EXISTS "pgsodium" WITH SCHEMA pgsodium;
            
            -- Grant schema usage
            GRANT USAGE ON SCHEMA pgsodium TO service_role;
            GRANT USAGE ON SCHEMA pgsodium TO postgres;
            GRANT USAGE ON SCHEMA pgsodium TO authenticated;
            GRANT USAGE ON SCHEMA pgsodium TO anon;
            
            -- Grant execute on all functions in pgsodium schema
            GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pgsodium TO service_role;
            GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pgsodium TO postgres;
            
            -- Grant specific function permissions if we have privileges
            IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_user AND rolsuper) THEN
                EXECUTE 'GRANT EXECUTE ON FUNCTION pgsodium.crypto_kdf_keygen TO service_role';
                EXECUTE 'GRANT EXECUTE ON FUNCTION pgsodium._crypto_aead_det_encrypt TO service_role';
                EXECUTE 'GRANT EXECUTE ON FUNCTION pgsodium._crypto_aead_det_decrypt TO service_role';
                EXECUTE 'GRANT EXECUTE ON FUNCTION pgsodium.crypto_sign_detached TO service_role';
                EXECUTE 'GRANT EXECUTE ON FUNCTION pgsodium.crypto_sign_final_verify TO service_role';
                EXECUTE 'GRANT EXECUTE ON FUNCTION pgsodium.crypto_sign_verify_detached TO service_role';
                RAISE NOTICE 'Successfully granted pgsodium function permissions';
            ELSE
                RAISE NOTICE 'Skipping specific pgsodium function grants - insufficient privileges';
            END IF;
            
            RAISE NOTICE 'pgsodium extension setup completed';
        EXCEPTION 
            WHEN OTHERS THEN
                RAISE NOTICE 'Could not setup pgsodium: %. Continuing without encryption features.', SQLERRM;
        END;
        
        -- Setup vault schema and permissions
        BEGIN
            -- Create vault schema if needed
            CREATE SCHEMA IF NOT EXISTS vault;
            
            -- Grant vault permissions
            GRANT USAGE ON SCHEMA vault TO supabase_storage_admin;
            GRANT ALL ON ALL TABLES IN SCHEMA vault TO supabase_storage_admin;
            GRANT ALL ON ALL ROUTINES IN SCHEMA vault TO supabase_storage_admin;
            GRANT ALL ON ALL SEQUENCES IN SCHEMA vault TO supabase_storage_admin;
            
            -- Grant roles
            GRANT supabase_storage_admin TO service_role;
            GRANT supabase_storage_admin TO authenticator;
            
            RAISE NOTICE 'Vault schema setup completed';
        EXCEPTION 
            WHEN OTHERS THEN
                RAISE NOTICE 'Could not setup vault: %. Continuing without vault features.', SQLERRM;
        END;
    ELSE
        RAISE NOTICE 'Not a Supabase environment - skipping pgsodium and vault setup';
    END IF;
END $$;

-- Install standard extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;

-- ========= Part 2: Core Table Definitions =========
-- All tables are created with IF NOT EXISTS for idempotency

CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
    email TEXT,
    role TEXT,
    deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.inventory (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    name TEXT NOT NULL,
    category TEXT,
    quantity INTEGER NOT NULL DEFAULT 0,
    cost NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    price NUMERIC(10, 2),
    reorder_point INTEGER,
    on_order_quantity INTEGER DEFAULT 0,
    last_sold_date DATE,
    landed_cost NUMERIC(10, 2),
    barcode TEXT,
    location_id UUID,
    version INTEGER DEFAULT 1 NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    source_platform TEXT,
    external_product_id TEXT,
    external_variant_id TEXT,
    external_quantity INTEGER,
    last_sync TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    deleted_by UUID
);

CREATE TABLE IF NOT EXISTS public.inventory_adjustments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    old_quantity INTEGER,
    new_quantity INTEGER NOT NULL,
    change_reason TEXT,
    adjusted_by UUID REFERENCES public.users(id),
    adjusted_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    address TEXT,
    is_default BOOLEAN DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.vendors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    vendor_name TEXT NOT NULL,
    contact_info TEXT,
    address TEXT,
    terms TEXT,
    account_number TEXT
);

CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform TEXT,
    external_id TEXT,
    customer_name TEXT NOT NULL,
    email TEXT,
    status TEXT,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_id UUID,
    sale_date TIMESTAMP WITH TIME ZONE NOT NULL,
    total_amount NUMERIC(10, 2) NOT NULL,
    sales_channel TEXT,
    platform TEXT,
    external_id TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.vendors(id) ON DELETE SET NULL,
    po_number TEXT NOT NULL,
    status TEXT DEFAULT 'draft',
    order_date DATE NOT NULL,
    expected_date DATE,
    total_amount NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS public.purchase_order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    po_id UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    quantity_ordered INTEGER NOT NULL,
    quantity_received INTEGER NOT NULL DEFAULT 0,
    unit_cost NUMERIC(10, 2) NOT NULL,
    tax_rate NUMERIC(5, 4) DEFAULT 0
);

CREATE TABLE IF NOT EXISTS public.integrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT false,
    last_sync_at TIMESTAMP WITH TIME ZONE,
    sync_status TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS public.sync_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type TEXT NOT NULL,
    status TEXT NOT NULL,
    records_synced INTEGER,
    error_message TEXT,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INTEGER DEFAULT 90,
    overstock_multiplier NUMERIC DEFAULT 3,
    high_value_threshold NUMERIC DEFAULT 1000,
    fast_moving_days INTEGER DEFAULT 30,
    predictive_stock_days INTEGER DEFAULT 7,
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    tax_rate NUMERIC DEFAULT 0,
    theme_primary_color TEXT DEFAULT '256 75% 61%',
    theme_background_color TEXT DEFAULT '222 83% 4%',
    theme_accent_color TEXT DEFAULT '217 33% 17%',
    custom_rules JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.channel_fees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name TEXT NOT NULL,
    percentage_fee NUMERIC(5, 4) NOT NULL,
    fixed_fee NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text
);

CREATE TABLE IF NOT EXISTS public.supplier_catalogs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id UUID NOT NULL REFERENCES public.vendors(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    supplier_sku TEXT,
    product_name TEXT,
    unit_cost NUMERIC(10, 2) NOT NULL,
    moq INTEGER DEFAULT 1,
    lead_time_days INTEGER,
    is_active BOOLEAN DEFAULT true
);

CREATE TABLE IF NOT EXISTS public.reorder_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    rule_type TEXT DEFAULT 'manual',
    min_stock INTEGER,
    max_stock INTEGER,
    reorder_quantity INTEGER
);

CREATE TABLE IF NOT EXISTS public.audit_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL,
    user_id uuid,
    action text NOT NULL,
    table_name text NOT NULL,
    record_id text,
    old_data jsonb,
    new_data jsonb,
    query_text text,
    ip_address inet,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.sync_state (
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type TEXT NOT NULL,
    last_processed_cursor TEXT,
    processed_count INTEGER DEFAULT 0,
    last_update TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY(integration_id, sync_type)
);

CREATE TABLE IF NOT EXISTS public.sync_errors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    error_message TEXT,
    stack_trace TEXT,
    attempt_number INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.export_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id UUID NOT NULL REFERENCES public.users(id),
    status TEXT NOT NULL DEFAULT 'pending',
    download_url TEXT,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.company_dashboard_metrics (
    company_id UUID PRIMARY KEY,
    total_skus BIGINT,
    inventory_value NUMERIC,
    low_stock_count BIGINT,
    last_refreshed TIMESTAMPTZ
);

-- ========= Part 3: Schema Migrations & Constraints =========

-- Fix existing duplicate SKUs before adding constraints
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM inventory
        GROUP BY company_id, sku
        HAVING COUNT(*) > 1
    ) THEN
        WITH duplicates AS (
            SELECT id, ROW_NUMBER() OVER (PARTITION BY company_id, sku ORDER BY id) as rn
            FROM inventory
        )
        UPDATE inventory
        SET sku = sku || '-DUP-' || id::text
        WHERE id IN (SELECT id FROM duplicates WHERE rn > 1);
    END IF;
END $$;

-- Add all unique constraints (wrapped for idempotency)
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_sku_per_company') THEN ALTER TABLE public.inventory ADD CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_variant_per_company') THEN ALTER TABLE public.inventory ADD CONSTRAINT unique_variant_per_company UNIQUE (company_id, source_platform, external_variant_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_location_name_per_company') THEN ALTER TABLE public.locations ADD CONSTRAINT unique_location_name_per_company UNIQUE (company_id, name); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_vendor_name_per_company') THEN ALTER TABLE public.vendors ADD CONSTRAINT unique_vendor_name_per_company UNIQUE (vendor_name, company_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_customer_per_platform') THEN ALTER TABLE public.customers ADD CONSTRAINT unique_customer_per_platform UNIQUE (company_id, platform, external_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_order_per_platform') THEN ALTER TABLE public.orders ADD CONSTRAINT unique_order_per_platform UNIQUE (company_id, platform, external_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_po_number_per_company') THEN ALTER TABLE public.purchase_orders ADD CONSTRAINT unique_po_number_per_company UNIQUE (company_id, po_number); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_platform_per_company') THEN ALTER TABLE public.integrations ADD CONSTRAINT unique_platform_per_company UNIQUE (company_id, platform); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_channel_per_company') THEN ALTER TABLE public.channel_fees ADD CONSTRAINT unique_channel_per_company UNIQUE (company_id, channel_name); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_supplier_sku') THEN ALTER TABLE public.supplier_catalogs ADD CONSTRAINT unique_supplier_sku UNIQUE (supplier_id, sku); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_reorder_rule_sku') THEN ALTER TABLE public.reorder_rules ADD CONSTRAINT unique_reorder_rule_sku UNIQUE (company_id, sku); END IF; END $$;

-- Add foreign key constraints
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_inventory_location') THEN ALTER TABLE public.inventory ADD CONSTRAINT fk_inventory_location FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE SET NULL; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_orders_customer') THEN ALTER TABLE public.orders ADD CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL; END IF; END $$;
DO $$ 
BEGIN 
    -- Only add the foreign key if the column exists
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'inventory' AND column_name = 'deleted_by') 
       AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_inventory_deleted_by') THEN 
        ALTER TABLE public.inventory ADD CONSTRAINT fk_inventory_deleted_by FOREIGN KEY (deleted_by) REFERENCES public.users(id); 
    END IF; 
END $$;

-- ========= Part 4: Functions & Triggers =========

-- Function to handle new user creation (Supabase-specific)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    new_company_id UUID;
    user_role TEXT := 'Owner';
    new_company_name TEXT;
BEGIN
    -- Check if auth schema exists (Supabase environment)
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'auth') THEN
        RAISE NOTICE 'Auth schema not found - skipping user creation trigger';
        RETURN new;
    END IF;

    -- Determine if this is an invite or a fresh sign-up
    IF new.invited_at IS NOT NULL THEN
        new_company_id := (new.raw_user_meta_data->>'company_id')::uuid;
        user_role := 'Member';

        IF new_company_id IS NULL THEN
            RAISE EXCEPTION 'Invited user must have a company_id in metadata.';
        END IF;
    ELSE
        user_role := 'Owner';
        new_company_id := (new.raw_user_meta_data->>'company_id')::uuid;
        new_company_name := COALESCE(new.raw_user_meta_data->>'company_name', new.email || '''s Company');
        INSERT INTO public.companies (id, name) VALUES (new_company_id, new_company_name);
    END IF;

    -- Insert into our public.users table
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new.id, new_company_id, new.email, user_role);

    -- For new owners, create default settings
    IF user_role = 'Owner' THEN
        INSERT INTO public.company_settings (company_id) VALUES (new_company_id) ON CONFLICT (company_id) DO NOTHING;
    END IF;
    
    -- Update app_metadata
    UPDATE auth.users
    SET app_metadata = COALESCE(app_metadata, '{}'::jsonb) || jsonb_build_object('role', user_role, 'company_id', new_company_id)
    WHERE id = new.id;
    
    RETURN new;
END;
$$;


-- Create auth user trigger only in Supabase environments
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'auth') THEN
        DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
        CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();
    END IF;
END $$;

-- Update timestamp function
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Batch upsert function
CREATE OR REPLACE FUNCTION public.batch_upsert_with_transaction(
    p_table_name text, p_records jsonb, p_conflict_columns text[]
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    company_id_from_jwt uuid;
    sanitized_records jsonb;
    update_set_clause text;
    query text;
BEGIN
    -- Get company_id from JWT if auth.jwt() exists
    BEGIN
        company_id_from_jwt := (auth.jwt() -> 'app_metadata' ->> 'company_id')::uuid;
    EXCEPTION
        WHEN OTHERS THEN
            -- If auth.jwt() doesn't exist, we're not in Supabase
            company_id_from_jwt := NULL;
    END;

    IF p_table_name NOT IN ('inventory', 'vendors', 'supplier_catalogs', 'reorder_rules', 'locations', 'customers') THEN
        RAISE EXCEPTION 'Invalid table for batch upsert: %', p_table_name;
    END IF;
    
    -- Only sanitize if we have a company_id
    IF company_id_from_jwt IS NOT NULL THEN
        SELECT jsonb_agg(jsonb_set(elem, '{company_id}', to_jsonb(company_id_from_jwt))) INTO sanitized_records FROM jsonb_array_elements(p_records) AS elem;
    ELSE
        sanitized_records := p_records;
    END IF;
    
    update_set_clause := (SELECT string_agg(format('%I = excluded.%I', key, key), ', ') FROM jsonb_object_keys(sanitized_records -> 0) AS key WHERE NOT (key = ANY(p_conflict_columns)));
    query := format('INSERT INTO %I SELECT * FROM jsonb_populate_recordset(null::%I, $1) ON CONFLICT (%s) DO UPDATE SET %s, updated_at = NOW();', p_table_name, p_table_name, array_to_string(p_conflict_columns, ', '), update_set_clause);
    EXECUTE query USING sanitized_records;
END;
$$;

-- Validate same company reference function
CREATE OR REPLACE FUNCTION validate_same_company_reference()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    ref_company_id uuid;
    current_company_id uuid;
BEGIN
    -- Check vendor reference for purchase_orders
    IF TG_TABLE_NAME = 'purchase_orders' AND NEW.supplier_id IS NOT NULL THEN
        SELECT company_id INTO ref_company_id FROM vendors WHERE id = NEW.supplier_id;
        IF ref_company_id != NEW.company_id THEN
            RAISE EXCEPTION 'Security violation: Cannot reference a vendor from a different company.';
        END IF;
    END IF;

    -- Check inventory location reference
    IF TG_TABLE_NAME = 'inventory' AND NEW.location_id IS NOT NULL THEN
        SELECT company_id INTO ref_company_id FROM locations WHERE id = NEW.location_id;
        IF ref_company_id != NEW.company_id THEN
            RAISE EXCEPTION 'Security violation: Cannot assign to a location from a different company.';
        END IF;
    END IF;

    -- Check order items reference inventory
    IF TG_TABLE_NAME = 'order_items' THEN
        SELECT company_id INTO ref_company_id FROM orders WHERE id = NEW.sale_id;
        IF NOT EXISTS (SELECT 1 FROM inventory WHERE sku = NEW.sku and company_id = ref_company_id) THEN
            RAISE EXCEPTION 'Security violation: SKU does not exist for this company.';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;

-- Audit trigger function
CREATE OR REPLACE FUNCTION audit_trigger()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    user_id_value uuid;
BEGIN
    -- Try to get user_id from auth.uid() if available
    BEGIN
        user_id_value := auth.uid();
    EXCEPTION
        WHEN OTHERS THEN
            user_id_value := NULL;
    END;

    INSERT INTO audit_log (company_id, user_id, action, table_name, record_id, old_data, new_data, ip_address)
    VALUES (
        COALESCE(NEW.company_id, OLD.company_id),
        user_id_value,
        TG_OP,
        TG_TABLE_NAME,
        COALESCE((NEW.id)::text, (OLD.id)::text),
        CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN row_to_json(OLD) ELSE NULL END,
        CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN row_to_json(NEW) ELSE NULL END,
        inet_client_addr()
    );
    RETURN COALESCE(NEW, OLD);
END;
$$;

-- Function to update an inventory item's metadata with optimistic locking
CREATE OR REPLACE FUNCTION public.update_inventory_item_with_lock(
    p_company_id UUID, 
    p_sku TEXT, 
    p_expected_version INTEGER,
    p_name TEXT,
    p_category TEXT,
    p_cost NUMERIC,
    p_reorder_point INTEGER,
    p_landed_cost NUMERIC,
    p_barcode TEXT,
    p_location_id UUID
) 
RETURNS SETOF public.inventory AS $$
DECLARE
    v_rows_updated INTEGER;
BEGIN
    UPDATE public.inventory i
    SET 
        name = p_name,
        category = p_category,
        cost = p_cost,
        reorder_point = p_reorder_point,
        landed_cost = p_landed_cost,
        barcode = p_barcode,
        location_id = p_location_id,
        version = version + 1
    WHERE i.company_id = p_company_id AND i.sku = p_sku AND i.version = p_expected_version;
        
    GET DIAGNOSTICS v_rows_updated = ROW_COUNT;
    
    IF v_rows_updated = 0 THEN
        RAISE EXCEPTION 'Update failed. The item may have been modified by someone else. Please refresh and try again.';
    END IF;
    
    -- Return the updated row
    RETURN QUERY SELECT * FROM public.inventory WHERE company_id = p_company_id AND sku = p_sku;
END;
$$ LANGUAGE plpgsql;

-- Purchase order receiving function
CREATE OR REPLACE FUNCTION public.receive_purchase_order_items(p_po_id uuid, p_items_to_receive jsonb, p_company_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE 
    item RECORD;
    v_already_received INTEGER;
    v_ordered_quantity INTEGER;
    v_can_receive INTEGER;
    total_ordered INTEGER;
    total_received INTEGER;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM purchase_orders WHERE id = p_po_id AND company_id = p_company_id) THEN
        RAISE EXCEPTION 'Purchase order not found or access denied';
    END IF;

    FOR item IN SELECT * FROM jsonb_to_recordset(p_items_to_receive) AS x(sku TEXT, quantity_to_receive INTEGER) LOOP
        SELECT poi.quantity_ordered, COALESCE(poi.quantity_received, 0) INTO v_ordered_quantity, v_already_received
        FROM purchase_order_items poi WHERE poi.po_id = p_po_id AND poi.sku = item.sku;
        
        IF NOT FOUND THEN RAISE EXCEPTION 'SKU % not found in this purchase order.', item.sku; END IF;
        v_can_receive := v_ordered_quantity - v_already_received;
        
        IF item.quantity_to_receive > v_can_receive THEN
            RAISE EXCEPTION 'Cannot receive % units for SKU %. Only % are outstanding.', item.quantity_to_receive, item.sku, v_can_receive;
        END IF;
        
        IF item.quantity_to_receive > 0 THEN
            UPDATE public.purchase_order_items SET quantity_received = quantity_received + item.quantity_to_receive WHERE po_id = p_po_id AND sku = item.sku;
            UPDATE public.inventory SET quantity = quantity + item.quantity_to_receive, on_order_quantity = on_order_quantity - item.quantity_to_receive WHERE company_id = p_company_id AND sku = item.sku;
            INSERT INTO inventory_ledger (company_id, sku, change_type, quantity_change, new_quantity, related_id)
            VALUES (p_company_id, item.sku, 'purchase_order_received', item.quantity_to_receive, (SELECT quantity FROM inventory WHERE sku=item.sku AND company_id=p_company_id), p_po_id);
        END IF;
    END LOOP;
    
    -- Update PO status after receiving
    SELECT SUM(quantity_ordered), SUM(quantity_received) INTO total_ordered, total_received FROM public.purchase_order_items WHERE po_id = p_po_id;
    IF total_received >= total_ordered THEN 
        UPDATE public.purchase_orders SET status = 'received' WHERE id = p_po_id;
    ELSIF total_received > 0 THEN 
        UPDATE public.purchase_orders SET status = 'partial' WHERE id = p_po_id;
    END IF;
END;
$$;

-- Dashboard metrics refresh function
CREATE OR REPLACE FUNCTION public.refresh_dashboard_metrics_for_company(p_company_id uuid)
RETURNS VOID AS $$
BEGIN
    DELETE FROM company_dashboard_metrics WHERE company_id = p_company_id;
    INSERT INTO company_dashboard_metrics (company_id, total_skus, inventory_value, low_stock_count, last_refreshed)
    SELECT p_company_id, COUNT(DISTINCT i.sku), SUM(i.quantity * i.cost), COUNT(CASE WHEN i.quantity <= i.reorder_point AND i.reorder_point > 0 THEN 1 END), NOW()
    FROM inventory i WHERE i.company_id = p_company_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get purchase orders function
CREATE OR REPLACE FUNCTION public.get_purchase_orders(
    p_company_id uuid,
    p_query text,
    p_limit integer,
    p_offset integer
)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    result_json json;
BEGIN
    WITH filtered_pos AS (
        SELECT
            po.id, po.company_id, po.supplier_id, po.po_number, po.status, po.order_date::text,
            po.expected_date::text, po.total_amount, po.notes, po.created_at::text, po.updated_at::text,
            v.vendor_name,
            v.contact_info as supplier_email
        FROM public.purchase_orders po
        LEFT JOIN public.vendors v ON po.supplier_id = v.id
        WHERE po.company_id = p_company_id
          AND (
            p_query IS NULL OR
            po.po_number ILIKE '%' || p_query || '%' OR
            v.vendor_name ILIKE '%' || p_query || '%'
          )
    ),
    count_query AS (
        SELECT count(*) as total FROM filtered_pos
    )
    SELECT json_build_object(
        'items', (SELECT json_agg(t) FROM (
            SELECT * FROM filtered_pos ORDER BY order_date DESC LIMIT p_limit OFFSET p_offset
        ) t),
        'totalCount', (SELECT total FROM count_query)
    ) INTO result_json;
    
    RETURN result_json;
END;
$$;

-- Get customers with stats function
CREATE OR REPLACE FUNCTION public.get_customers_with_stats(
    p_company_id uuid,
    p_query text,
    p_limit integer,
    p_offset integer
)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    result_json json;
BEGIN
    WITH customer_stats AS (
        SELECT
            c.id,
            c.company_id,
            c.platform,
            c.external_id,
            c.customer_name,
            c.email,
            c.status,
            c.deleted_at,
            c.created_at,
            COUNT(o.id) as total_orders,
            COALESCE(SUM(o.total_amount), 0) as total_spend
        FROM public.customers c
        LEFT JOIN public.orders o ON c.id = o.customer_id
        WHERE c.company_id = p_company_id
          AND c.deleted_at IS NULL
          AND (
            p_query IS NULL OR
            c.customer_name ILIKE '%' || p_query || '%' OR
            c.email ILIKE '%' || p_query || '%'
          )
        GROUP BY c.id
    ),
    count_query AS (
        SELECT count(*) as total FROM customer_stats
    )
    SELECT json_build_object(
        'items', (SELECT json_agg(cs) FROM (
            SELECT * FROM customer_stats ORDER BY total_spend DESC LIMIT p_limit OFFSET p_offset
        ) cs),
        'totalCount', (SELECT total FROM count_query)
    ) INTO result_json;
    
    RETURN result_json;
END;
$$;

-- ========= Part 5: Row-Level Security (RLS) Policies =========

-- RLS helper functions (safe for non-Supabase environments)
CREATE OR REPLACE FUNCTION public.current_user_company_id()
RETURNS uuid LANGUAGE sql STABLE AS $$
    SELECT CASE 
        WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'jwt' AND pronamespace = 'auth'::regnamespace) THEN
            (auth.jwt()->'app_metadata'->>'company_id')::uuid
        ELSE
            NULL::uuid
    END;
$$;

CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE 
        WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'jwt' AND pronamespace = 'auth'::regnamespace) THEN
            (auth.jwt()->'app_metadata'->>'role')::text
        ELSE
            NULL::text
    END;
$$;

-- Enable RLS and create policies only if auth functions exist
DO $$
DECLARE
    t_name TEXT;
    has_auth BOOLEAN;
BEGIN
    -- Check if auth.jwt() exists
    SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'jwt' AND pronamespace = 'auth'::regnamespace) INTO has_auth;
    
    IF has_auth THEN
        -- Enable RLS on all tables with a direct company_id
        FOR t_name IN SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN (
            'users', 'company_settings', 'inventory', 'customers', 'orders', 'vendors', 'reorder_rules', 
            'purchase_orders', 'integrations', 'channel_fees', 'locations', 'inventory_ledger', 'audit_log', 
            'sync_errors', 'export_jobs', 'inventory_adjustments'
        ) LOOP
            EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t_name);
            EXECUTE format('DROP POLICY IF EXISTS "Enable all access for own company" ON public.%I;', t_name);
            EXECUTE format('CREATE POLICY "Enable all access for own company" ON public.%I FOR ALL USING (company_id = public.current_user_company_id()) WITH CHECK (company_id = public.current_user_company_id());', t_name);
        END LOOP;

        -- Specific policies for tables that join to get company_id
        -- order_items
        ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS "Enable all access for own company" ON public.order_items;
        CREATE POLICY "Enable all access for own company" ON public.order_items FOR ALL
            USING ((SELECT company_id FROM public.orders WHERE id = sale_id) = public.current_user_company_id());

        -- purchase_order_items
        ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS "Enable all access for own company" ON public.purchase_order_items;
        CREATE POLICY "Enable all access for own company" ON public.purchase_order_items FOR ALL
            USING ((SELECT company_id FROM public.purchase_orders WHERE id = po_id) = public.current_user_company_id());

        -- supplier_catalogs
        ALTER TABLE public.supplier_catalogs ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS "Enable all access for own company" ON public.supplier_catalogs;
        CREATE POLICY "Enable all access for own company" ON public.supplier_catalogs FOR ALL
            USING ((SELECT company_id FROM public.vendors WHERE id = supplier_id) = public.current_user_company_id());
            
        -- sync_logs
        ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS "Enable all access for own company" ON public.sync_logs;
        CREATE POLICY "Enable all access for own company" ON public.sync_logs FOR ALL
            USING ((SELECT company_id FROM public.integrations WHERE id = integration_id) = public.current_user_company_id());
            
        -- sync_state
        ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS "Enable all access for own company" ON public.sync_state;
        CREATE POLICY "Enable all access for own company" ON public.sync_state FOR ALL
            USING ((SELECT company_id FROM public.integrations WHERE id = integration_id) = public.current_user_company_id())
            WITH CHECK ((SELECT company_id FROM public.integrations WHERE id = integration_id) = public.current_user_company_id());

        -- Policy for companies table
        ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS "Users can see their own company" ON public.companies;
        CREATE POLICY "Users can see their own company" ON public.companies FOR SELECT
            USING (id = public.current_user_company_id());
    ELSE
        RAISE NOTICE 'Auth functions not found - skipping RLS policies';
    END IF;
END $$;

-- ========= Part 6: Apply Triggers =========

-- Validation triggers
DROP TRIGGER IF EXISTS validate_purchase_order_refs ON public.purchase_orders;
CREATE TRIGGER validate_purchase_order_refs BEFORE INSERT OR UPDATE ON public.purchase_orders
    FOR EACH ROW EXECUTE FUNCTION validate_same_company_reference();

DROP TRIGGER IF EXISTS validate_inventory_location_ref ON public.inventory;
CREATE TRIGGER validate_inventory_location_ref BEFORE INSERT OR UPDATE ON public.inventory
    FOR EACH ROW EXECUTE FUNCTION validate_same_company_reference();
    
DROP TRIGGER IF EXISTS validate_order_item_refs ON public.order_items;
CREATE TRIGGER validate_order_item_refs BEFORE INSERT ON public.order_items
    FOR EACH ROW EXECUTE FUNCTION validate_same_company_reference();

-- Update timestamp trigger
DROP TRIGGER IF EXISTS set_inventory_updated_at ON public.inventory;
CREATE TRIGGER set_inventory_updated_at BEFORE UPDATE ON public.inventory 
    FOR EACH ROW EXECUTE PROCEDURE public.update_updated_at_column();

-- Apply audit triggers to critical tables
DO $$
DECLARE
    t_name TEXT;
BEGIN
    FOR t_name IN SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN (
        'inventory', 'users', 'company_settings', 'purchase_orders', 'orders', 'locations', 'vendors'
    ) LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS audit_changes ON public.%I;', t_name);
        EXECUTE format('CREATE TRIGGER audit_changes AFTER INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION audit_trigger();', t_name);
    END LOOP;
END $$;

-- ========= Script Completion =========
DO $$
BEGIN
    RAISE NOTICE 'InvoChat database setup completed successfully!';
END $$;
`;