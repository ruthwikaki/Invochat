
export const SETUP_SQL_SCRIPT = `-- InvoChat Database Setup Script
-- This script is idempotent and can be safely re-run on an existing database.

-- ========= Part 1: Core Table Definitions =========
-- All tables are created here with their essential columns.
-- Alterations and constraints will be applied in a later section.

create extension if not exists "uuid-ossp" with schema extensions;

CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- This table is for app-specific user data and roles, linked to auth.users
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
    email TEXT,
    role TEXT,
    deleted_at TIMESTAMPTZ -- For soft-deleting user association
);

-- This table contains all inventory items for all companies.
-- RLS policies will ensure data isolation.
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
    version INTEGER DEFAULT 1 NOT NULL, -- For optimistic locking
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    source_platform TEXT,
    external_product_id TEXT,
    external_variant_id TEXT
);

-- This table tracks manual changes to inventory for audit purposes.
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
    status TEXT, -- for soft deletes
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

-- This table is critical for security and compliance.
CREATE TABLE IF NOT EXISTS public.audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  user_id uuid, -- Nullable for system actions
  action text NOT NULL,
  table_name text NOT NULL,
  record_id text,
  old_data jsonb,
  new_data jsonb,
  query_text text,
  ip_address inet,
  created_at timestamptz DEFAULT now()
);

-- ========= Part 2: Schema Migrations & Constraints =========

-- Fix existing duplicate SKUs before adding the unique constraint.
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
END;
$$;

-- Add all unique constraints to enforce data integrity at the DB level.
ALTER TABLE public.inventory ADD CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku);
ALTER TABLE public.locations ADD CONSTRAINT unique_location_name_per_company UNIQUE (company_id, name);
ALTER TABLE public.vendors ADD CONSTRAINT unique_vendor_name_per_company UNIQUE (company_id, vendor_name);
ALTER TABLE public.customers ADD CONSTRAINT unique_customer_per_platform UNIQUE (company_id, platform, external_id);
ALTER TABLE public.orders ADD CONSTRAINT unique_order_per_platform UNIQUE (company_id, platform, external_id);
ALTER TABLE public.purchase_orders ADD CONSTRAINT unique_po_number_per_company UNIQUE (company_id, po_number);
ALTER TABLE public.integrations ADD CONSTRAINT unique_platform_per_company UNIQUE (company_id, platform);
ALTER TABLE public.channel_fees ADD CONSTRAINT unique_channel_per_company UNIQUE (company_id, channel_name);
ALTER TABLE public.supplier_catalogs ADD CONSTRAINT unique_supplier_sku UNIQUE (supplier_id, sku);
ALTER TABLE public.reorder_rules ADD CONSTRAINT unique_reorder_rule_sku UNIQUE (company_id, sku);


-- Add foreign key constraints where they might be missing.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_inventory_location') THEN
        ALTER TABLE public.inventory ADD CONSTRAINT fk_inventory_location
        FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE SET NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_orders_customer') THEN
        ALTER TABLE public.orders ADD CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL;
    END IF;
END;
$$;


-- ========= Part 3: Functions & Triggers =========

-- Function to handle new user creation.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  new_company_id UUID;
  user_role TEXT := 'Owner';
  new_company_name TEXT;
BEGIN
  new_company_name := COALESCE(new.raw_user_meta_data->>'company_name', 'My Company');
  INSERT INTO public.companies (name) VALUES (new_company_name) RETURNING id INTO new_company_id;
  INSERT INTO public.users (id, company_id, email, role) VALUES (new.id, new_company_id, new.email, user_role);
  INSERT INTO public.company_settings (company_id) VALUES (new_company_id) ON CONFLICT (company_id) DO NOTHING;
  UPDATE auth.users SET app_metadata = jsonb_set(COALESCE(app_metadata, '{}'::jsonb), '{role}', to_jsonb(user_role)) WHERE id = new.id;
  UPDATE auth.users SET app_metadata = jsonb_set(COALESCE(app_metadata, '{}'::jsonb), '{company_id}', to_jsonb(new_company_id)) WHERE id = new.id;
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created on auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Secure batch upsert function that enforces company_id from the user's session.
CREATE OR REPLACE FUNCTION public.batch_upsert_with_transaction(
  p_table_name text, p_records jsonb, p_conflict_columns text[]
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  company_id_from_jwt uuid := (auth.jwt() -> 'app_metadata' ->> 'company_id')::uuid;
  sanitized_records jsonb;
  update_set_clause text;
  query text;
BEGIN
  IF p_table_name NOT IN ('inventory', 'vendors', 'supplier_catalogs', 'reorder_rules', 'locations', 'customers') THEN
    RAISE EXCEPTION 'Invalid table for batch upsert: %', p_table_name;
  END IF;
  SELECT jsonb_agg(jsonb_set(elem, '{company_id}', to_jsonb(company_id_from_jwt))) INTO sanitized_records FROM jsonb_array_elements(p_records) AS elem;
  update_set_clause := (SELECT string_agg(format('%I = excluded.%I', key, key), ', ') FROM jsonb_object_keys(sanitized_records -> 0) AS key WHERE NOT (key = ANY(p_conflict_columns)));
  query := format('INSERT INTO %I SELECT * FROM jsonb_populate_recordset(null::%I, $1) ON CONFLICT (%s) DO UPDATE SET %s;', p_table_name, p_table_name, array_to_string(p_conflict_columns, ', '), update_set_clause);
  EXECUTE query USING sanitized_records;
END;
$$;

-- Secure function to prevent cross-tenant references
CREATE OR REPLACE FUNCTION validate_same_company_reference()
RETURNS TRIGGER AS $$
DECLARE
  ref_company_id uuid;
  current_company_id uuid;
BEGIN
  current_company_id := NEW.company_id;
  
  -- Check vendor reference for purchase_orders
  IF TG_TABLE_NAME = 'purchase_orders' AND NEW.supplier_id IS NOT NULL THEN
    SELECT company_id INTO ref_company_id FROM vendors WHERE id = NEW.supplier_id;
    IF ref_company_id != current_company_id THEN
      RAISE EXCEPTION 'Security violation: Cannot reference a vendor from a different company.';
    END IF;
  END IF;

  -- Check inventory location reference
  IF TG_TABLE_NAME = 'inventory' AND NEW.location_id IS NOT NULL THEN
    SELECT company_id INTO ref_company_id FROM locations WHERE id = NEW.location_id;
    IF ref_company_id != current_company_id THEN
      RAISE EXCEPTION 'Security violation: Cannot assign to a location from a different company.';
    END IF;
  END IF;

  -- Check order items reference inventory
   IF TG_TABLE_NAME = 'order_items' AND NEW.sku IS NOT NULL THEN
    SELECT company_id INTO ref_company_id FROM orders WHERE id = NEW.sale_id;
    IF NOT EXISTS (SELECT 1 FROM inventory WHERE sku = NEW.sku and company_id = ref_company_id) THEN
      RAISE EXCEPTION 'Security violation: SKU does not exist for this company.';
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- Audit Trigger: Logs all changes to sensitive tables
CREATE OR REPLACE FUNCTION audit_trigger()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO audit_log (company_id, user_id, action, table_name, record_id, old_data, new_data, ip_address)
  VALUES (COALESCE(NEW.company_id, OLD.company_id), auth.uid(), TG_OP, TG_TABLE_NAME, COALESCE((NEW.id)::text, (OLD.id)::text),
    CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN row_to_json(OLD) ELSE NULL END,
    CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN row_to_json(NEW) ELSE NULL END,
    inet_client_addr()
  );
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Optimistic Locking for Inventory Updates
CREATE OR REPLACE FUNCTION update_inventory_with_lock(
    p_company_id UUID, p_sku TEXT, p_new_quantity INTEGER, p_expected_version INTEGER,
    p_change_reason TEXT, p_user_id UUID
) RETURNS JSON AS $$
DECLARE
    v_rows_updated INTEGER;
    v_old_quantity INTEGER;
BEGIN
    SELECT quantity INTO v_old_quantity FROM inventory WHERE company_id = p_company_id AND sku = p_sku;
    
    UPDATE inventory SET quantity = p_new_quantity, version = version + 1, updated_at = NOW()
    WHERE company_id = p_company_id AND sku = p_sku AND version = p_expected_version;
        
    GET DIAGNOSTICS v_rows_updated = ROW_COUNT;
    
    IF v_rows_updated = 0 THEN
        RETURN json_build_object('success', false, 'error', 'Version mismatch');
    END IF;
    
    INSERT INTO inventory_adjustments (company_id, sku, old_quantity, new_quantity, change_reason, adjusted_by, adjusted_at)
    VALUES (p_company_id, p_sku, v_old_quantity, p_new_quantity, p_change_reason, p_user_id, NOW());
    
    RETURN json_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Purchase Order Over-Receiving Prevention
CREATE OR REPLACE FUNCTION public.receive_purchase_order_items(p_po_id uuid, p_items_to_receive jsonb, p_company_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE 
    item RECORD; v_already_received INTEGER; v_ordered_quantity INTEGER; v_can_receive INTEGER;
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
    DECLARE total_ordered INTEGER; total_received INTEGER;
    BEGIN
        SELECT SUM(quantity_ordered), SUM(quantity_received) INTO total_ordered, total_received FROM public.purchase_order_items WHERE po_id = p_po_id;
        IF total_received >= total_ordered THEN UPDATE public.purchase_orders SET status = 'received' WHERE id = p_po_id;
        ELSIF total_received > 0 THEN UPDATE public.purchase_orders SET status = 'partial' WHERE id = p_po_id;
        END IF;
    END;
END;
$$;


-- Replaces the materialized view with a secure, on-demand function.
-- A cached table is used for performance, populated by this per-company function.
CREATE TABLE IF NOT EXISTS public.company_dashboard_metrics (
  company_id UUID PRIMARY KEY, total_skus BIGINT, inventory_value NUMERIC, low_stock_count BIGINT, last_refreshed TIMESTAMPTZ
);
CREATE OR REPLACE FUNCTION public.refresh_dashboard_metrics_for_company(p_company_id uuid)
RETURNS VOID AS $$
BEGIN
    DELETE FROM company_dashboard_metrics WHERE company_id = p_company_id;
    INSERT INTO company_dashboard_metrics (company_id, total_skus, inventory_value, low_stock_count, last_refreshed)
    SELECT p_company_id, COUNT(DISTINCT i.sku), SUM(i.quantity * i.cost), COUNT(CASE WHEN i.quantity <= i.reorder_point AND i.reorder_point > 0 THEN 1 END), NOW()
    FROM inventory i WHERE i.company_id = p_company_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ========= Part 4: Row-Level Security (RLS) Policies =========

-- Helper function for RLS policies
CREATE OR REPLACE FUNCTION public.current_user_company_id()
RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT (auth.jwt()->'app_metadata'->>'company_id')::uuid;
$$;

-- Function to get user role
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT (auth.jwt()->'app_metadata'->>'role')::text;
$$;

-- Generic policy creation for simple company_id checks
DO $$
DECLARE
    t_name TEXT;
BEGIN
    FOR t_name IN SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN (
        'users', 'company_settings', 'inventory', 'customers', 'orders', 'vendors', 'reorder_rules', 
        'purchase_orders', 'integrations', 'channel_fees', 'locations', 'inventory_ledger', 'audit_log', 'sync_logs'
    ) LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t_name);
        EXECUTE format('DROP POLICY IF EXISTS "Enable all access for own company" ON public.%I;', t_name);
        EXECUTE format('CREATE POLICY "Enable all access for own company" ON public.%I FOR ALL USING (company_id = public.current_user_company_id()) WITH CHECK (company_id = public.current_user_company_id());', t_name);
    END LOOP;
END;
$$;

-- Specific policies for tables without a direct company_id column
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Enable all access for own company" ON public.order_items;
CREATE POLICY "Enable all access for own company" ON public.order_items FOR ALL
  USING ((SELECT company_id FROM public.orders WHERE id = sale_id) = public.current_user_company_id());

ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Enable all access for own company" ON public.purchase_order_items;
CREATE POLICY "Enable all access for own company" ON public.purchase_order_items FOR ALL
  USING ((SELECT company_id FROM public.purchase_orders WHERE id = po_id) = public.current_user_company_id());

ALTER TABLE public.supplier_catalogs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Enable all access for own company" ON public.supplier_catalogs;
CREATE POLICY "Enable all access for own company" ON public.supplier_catalogs FOR ALL
  USING ((SELECT company_id FROM public.vendors WHERE id = supplier_id) = public.current_user_company_id());

-- Policy for companies table
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can see their own company" ON public.companies;
CREATE POLICY "Users can see their own company" ON public.companies FOR SELECT
  USING (id = public.current_user_company_id());

-- ========= Part 5: Apply Triggers =========
DROP TRIGGER IF EXISTS validate_purchase_order_refs ON public.purchase_orders;
CREATE TRIGGER validate_purchase_order_refs BEFORE INSERT OR UPDATE ON public.purchase_orders
  FOR EACH ROW EXECUTE FUNCTION validate_same_company_reference();

DROP TRIGGER IF EXISTS validate_inventory_location_ref ON public.inventory;
CREATE TRIGGER validate_inventory_location_ref BEFORE INSERT OR UPDATE ON public.inventory
  FOR EACH ROW EXECUTE FUNCTION validate_same_company_reference();
  
DROP TRIGGER IF EXISTS validate_order_item_refs ON public.order_items;
CREATE TRIGGER validate_order_item_refs BEFORE INSERT ON public.order_items
  FOR EACH ROW EXECUTE FUNCTION validate_same_company_reference();

-- Apply Audit Triggers to all critical tables
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
END;
$$;
