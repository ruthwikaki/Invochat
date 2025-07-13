-- InvoChat Finalization & Correction Script
-- This script applies only the necessary final changes to the database.
-- It is idempotent and safe to run on the current database state.

-- 1. Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Clean up any remaining deprecated tables
-- These tables have been replaced by the new schema (products, orders, etc.)
DROP TABLE IF EXISTS public.inventory CASCADE;
DROP TABLE IF EXISTS public.sales CASCADE;
DROP TABLE IF EXISTS public.sale_items CASCADE;
DROP TABLE IF EXISTS public.sync_logs CASCADE;
DROP TABLE IF EXISTS public.sync_state CASCADE;

-- 3. Alter existing tables to match final schema
-- Remove the deprecated access_token column from integrations table.
-- Tokens are now securely stored in Supabase Vault.
ALTER TABLE public.integrations DROP COLUMN IF EXISTS access_token;


-- 4. Create missing functions and triggers

-- Function to get the company_id for the currently authenticated user
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid,
    (SELECT company_id FROM public.users WHERE id = auth.uid())
  );
$$;
REVOKE ALL ON FUNCTION public.get_current_company_id() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_current_company_id() TO authenticated;


-- Function to create a company and link it to a new user upon signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  company_id uuid;
  user_email text;
  user_id uuid;
BEGIN
  -- Extract user ID and email from the trigger data
  user_id := new.id;
  user_email := new.email;

  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (new.raw_user_meta_data ->> 'company_name')
  RETURNING id INTO company_id;

  -- Insert the user into our public.users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (user_id, company_id, user_email, 'Owner');

  -- Update the user's app_metadata in auth.users
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', 'Owner')
  WHERE id = user_id;

  RETURN new;
END;
$$;

-- Trigger to execute handle_new_user on new user creation in auth.users
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- Function to update inventory quantities based on ledger entries (CRITICAL)
-- This ensures inventory levels are always accurate.
CREATE OR REPLACE FUNCTION public.update_inventory_from_ledger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.product_variants
  SET inventory_quantity = inventory_quantity + NEW.quantity_change,
      updated_at = NOW()
  WHERE id = NEW.variant_id;
  RETURN NEW;
END;
$$;

-- Trigger to fire the inventory update function after a ledger entry is created.
CREATE OR REPLACE TRIGGER on_inventory_ledger_insert
  AFTER INSERT ON public.inventory_ledger
  FOR EACH ROW
  EXECUTE FUNCTION public.update_inventory_from_ledger();


-- Function to handle recording an order from a platform like Shopify
-- This is a transactional function to ensure data integrity.
CREATE OR REPLACE FUNCTION public.record_order_from_platform(
    p_company_id uuid,
    p_order_payload jsonb,
    p_platform text
)
RETURNS uuid AS $$
DECLARE
    v_customer_id uuid;
    v_order_id uuid;
    v_order_number text;
    v_line_item jsonb;
    v_variant_id uuid;
    v_product_id uuid;
    v_cost_at_time int;
BEGIN
    -- Step 1: Find or Create Customer
    SELECT id INTO v_customer_id FROM public.customers
    WHERE email = p_order_payload -> 'customer' ->> 'email' AND company_id = p_company_id;

    IF v_customer_id IS NULL THEN
        INSERT INTO public.customers (company_id, customer_name, email)
        VALUES (p_company_id, p_order_payload -> 'customer' ->> 'first_name' || ' ' || p_order_payload -> 'customer' ->> 'last_name', p_order_payload -> 'customer' ->> 'email')
        RETURNING id INTO v_customer_id;
    END IF;

    -- Step 2: Create or Update Order
    v_order_number := p_order_payload ->> 'name'; -- Shopify uses 'name' for order number like '#1001'

    INSERT INTO public.orders (
        id, company_id, order_number, external_order_id, customer_id, financial_status, fulfillment_status,
        currency, subtotal, total_tax, total_shipping, total_discounts, total_amount, source_platform, created_at, updated_at
    )
    VALUES (
        uuid_generate_v4(), p_company_id, v_order_number, p_order_payload ->> 'id', v_customer_id, p_order_payload ->> 'financial_status',
        p_order_payload ->> 'fulfillment_status', p_order_payload ->> 'currency',
        (p_order_payload ->> 'subtotal_price')::numeric * 100, (p_order_payload ->> 'total_tax')::numeric * 100,
        (p_order_payload ->> 'total_shipping_price_set' -> 'shop_money' ->> 'amount')::numeric * 100,
        (p_order_payload ->> 'total_discounts')::numeric * 100, (p_order_payload ->> 'total_price')::numeric * 100,
        p_platform, (p_order_payload ->> 'created_at')::timestamptz, (p_order_payload ->> 'updated_at')::timestamptz
    )
    ON CONFLICT (company_id, external_order_id) DO UPDATE SET
        financial_status = EXCLUDED.financial_status,
        fulfillment_status = EXCLUDED.fulfillment_status,
        total_amount = EXCLUDED.total_amount,
        updated_at = EXCLUDED.updated_at
    RETURNING id INTO v_order_id;

    -- Step 3: Process Line Items
    FOR v_line_item IN SELECT * FROM jsonb_array_elements(p_order_payload -> 'line_items')
    LOOP
        SELECT id, product_id, cost INTO v_variant_id, v_product_id, v_cost_at_time
        FROM public.product_variants
        WHERE external_variant_id = v_line_item ->> 'variant_id' AND company_id = p_company_id;

        IF v_variant_id IS NOT NULL THEN
            INSERT INTO public.order_line_items (
                order_id, company_id, variant_id, product_id, product_name, variant_title, sku, quantity, price,
                total_discount, external_line_item_id, cost_at_time
            ) VALUES (
                v_order_id, p_company_id, v_variant_id, v_product_id, v_line_item ->> 'title', v_line_item ->> 'variant_title',
                v_line_item ->> 'sku', (v_line_item ->> 'quantity')::int, (v_line_item ->> 'price')::numeric * 100,
                (v_line_item ->> 'total_discount')::numeric * 100, v_line_item ->> 'id', v_cost_at_time
            ) ON CONFLICT DO NOTHING;
        END IF;
    END LOOP;

    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql;

-- Grant permissions for this function
GRANT EXECUTE ON FUNCTION public.record_order_from_platform(uuid, jsonb, text) TO service_role;


-- Final step: Re-enable RLS and create policies for all tables
-- This ensures security policies are correctly applied after all changes.

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_line_items ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE PROCEDURE public.create_rls_policy(table_name TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
  EXECUTE format('
    CREATE POLICY "Users can only see their own company''s data."
    ON public.%I FOR ALL
    USING (company_id = public.get_current_company_id());
  ', table_name);
END;
$$;

DO $$
DECLARE
    t_name TEXT;
BEGIN
    FOR t_name IN
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'public'
          AND tablename IN (
            'company_settings', 'products', 'product_variants', 'customers',
            'orders', 'order_line_items', 'suppliers', 'conversations',
            'messages', 'integrations', 'inventory_ledger', 'refund_line_items'
          )
    LOOP
        EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY;', t_name);
        EXECUTE format('DROP POLICY IF EXISTS "Users can only see their own company''s data." ON public.%I;', t_name);
        CALL public.create_rls_policy(t_name);
    END LOOP;
END;
$$;

-- Special policy for the companies table
DROP POLICY IF EXISTS "Users can only see their own company." ON public.companies;
CREATE POLICY "Users can only see their own company."
ON public.companies FOR SELECT
USING (id = public.get_current_company_id());

-- Grant usage on schema to roles
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO postgres, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO postgres, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO postgres, service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO postgres, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres, service_role;

GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.companies, public.company_settings, public.products, public.product_variants, public.customers, public.orders, public.order_line_items, public.suppliers, public.conversations, public.messages, public.integrations TO authenticated;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
