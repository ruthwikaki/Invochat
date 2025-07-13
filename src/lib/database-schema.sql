-- InvoChat Database Schema
-- Version: 2.0
-- Description: This script refactors the database to a more relational and scalable model.

-- Drop old tables if they exist
DROP TABLE IF EXISTS public.inventory CASCADE;
DROP TABLE IF EXISTS public.sales CASCADE;
DROP TABLE IF EXISTS public.sale_items CASCADE;
DROP TABLE IF EXISTS public.sync_logs CASCADE;
DROP TABLE IF EXISTS public.sync_state CASCADE;


-- Drop the old access_token column from integrations if it exists
DO $$
BEGIN
   IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'integrations'
        AND column_name = 'access_token'
    )
   THEN
      ALTER TABLE public.integrations DROP COLUMN access_token;
   END IF;
END;
$$;


-- Helper procedure to create RLS policies easily
-- This avoids repetitive code for enabling RLS and creating policies.
DROP FUNCTION IF EXISTS create_rls_policy(TEXT) CASCADE;
DROP PROCEDURE IF EXISTS create_rls_policy(TEXT) CASCADE;

CREATE OR REPLACE PROCEDURE create_rls_policy(
    table_name_param TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    select_policy_name TEXT;
    insert_policy_name TEXT;
    update_policy_name TEXT;
    delete_policy_name TEXT;
BEGIN
    -- Construct policy names
    select_policy_name := 'select_policy_for_' || table_name_param;
    insert_policy_name := 'insert_policy_for_' || table_name_param;
    update_policy_name := 'update_policy_for_' || table_name_param;
    delete_policy_name := 'delete_policy_for_' || table_name_param;

    -- Enable RLS on the specified table
    EXECUTE 'ALTER TABLE public.' || quote_ident(table_name_param) || ' ENABLE ROW LEVEL SECURITY';
    EXECUTE 'ALTER TABLE public.' || quote_ident(table_name_param) || ' FORCE ROW LEVEL SECURITY';

    -- Create policies
    -- SELECT: Users can only see their own company's data.
    EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(select_policy_name) || ' ON public.' || quote_ident(table_name_param);
    EXECUTE 'CREATE POLICY ' || quote_ident(select_policy_name) || ' ON public.' || quote_ident(table_name_param) || ' FOR SELECT USING (company_id = get_current_company_id())';

    -- INSERT: Users can only add data for their own company.
    EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(insert_policy_name) || ' ON public.' || quote_ident(table_name_param);
    EXECUTE 'CREATE POLICY ' || quote_ident(insert_policy_name) || ' ON public.' || quote_ident(table_name_param) || ' FOR INSERT WITH CHECK (company_id = get_current_company_id())';

    -- UPDATE: Users can only update data for their own company.
    EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(update_policy_name) || ' ON public.' || quote_ident(table_name_param);
    EXECUTE 'CREATE POLICY ' || quote_ident(update_policy_name) || ' ON public.' || quote_ident(table_name_param) || ' FOR UPDATE USING (company_id = get_current_company_id()) WITH CHECK (company_id = get_current_company_id())';

    -- DELETE: Users can only delete data for their own company.
    EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(delete_policy_name) || ' ON public.' || quote_ident(table_name_param);
    EXECUTE 'CREATE POLICY ' || quote_ident(delete_policy_name) || ' ON public.' || quote_ident(table_name_param) || ' FOR DELETE USING (company_id = get_current_company_id())';
END;
$$;


-- Create a function to safely get the current user's company_id
CREATE OR REPLACE FUNCTION get_current_company_id()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid,
    (auth.jwt() -> 'app_metadata' ->> 'company_id')::uuid
  );
$$;


-- Create a function that handles new user sign-ups.
-- This function creates a company for the new user and links them.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
  user_company_name text;
BEGIN
  -- Extract company name from user metadata, defaulting if not present
  user_company_name := COALESCE(new.raw_user_meta_data->>'company_name', 'My Company');

  -- Create a new company
  INSERT INTO public.companies (name)
  VALUES (user_company_name)
  RETURNING id INTO new_company_id;

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = jsonb_set(
    COALESCE(raw_app_meta_data, '{}'::jsonb),
    '{company_id}',
    to_jsonb(new_company_id)
  )
  WHERE id = new.id;

  -- Create default settings for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (new_company_id);

  RETURN new;
END;
$$;

-- Create a trigger to call the handle_new_user function on new user creation
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- Create a function to update inventory based on ledger entries
CREATE OR REPLACE FUNCTION public.update_inventory_from_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.product_variants
  SET inventory_quantity = NEW.new_quantity,
      updated_at = NOW()
  WHERE id = NEW.variant_id;
  RETURN NEW;
END;
$$;

-- Create a trigger to call the inventory update function
DROP TRIGGER IF EXISTS on_inventory_ledger_insert ON public.inventory_ledger;
CREATE TRIGGER on_inventory_ledger_insert
  AFTER INSERT ON public.inventory_ledger
  FOR EACH ROW
  EXECUTE FUNCTION public.update_inventory_from_ledger();


-- === Webhook Security Table and Policies ===
-- Table to store processed webhook IDs to prevent replay attacks
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    webhook_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_webhook_per_integration UNIQUE (integration_id, webhook_id)
);

COMMENT ON TABLE public.webhook_events IS 'Stores unique webhook IDs to prevent replay attacks.';

-- Enable RLS and apply policies for webhook_events
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS select_policy_for_webhook_events ON public.webhook_events;
CREATE POLICY select_policy_for_webhook_events ON public.webhook_events FOR SELECT
USING ((SELECT company_id FROM public.integrations WHERE id = webhook_events.integration_id) = get_current_company_id());

DROP POLICY IF EXISTS insert_policy_for_webhook_events ON public.webhook_events;
CREATE POLICY insert_policy_for_webhook_events ON public.webhook_events FOR INSERT
WITH CHECK ((SELECT company_id FROM public.integrations WHERE id = webhook_events.integration_id) = get_current_company_id());


-- === RLS Policy for Customer Addresses ===
-- This policy ensures users can only access addresses linked to customers within their own company.
ALTER TABLE public.customer_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_addresses FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS select_policy_for_customer_addresses ON public.customer_addresses;
CREATE POLICY select_policy_for_customer_addresses ON public.customer_addresses FOR ALL
USING (
    EXISTS (
        SELECT 1
        FROM public.customers c
        WHERE c.id = customer_addresses.customer_id
        AND c.company_id = get_current_company_id()
    )
);

-- =================================================================
-- Apply RLS policies to all company-specific tables
-- =================================================================
-- This ensures strict data separation between different companies.
CALL create_rls_policy('companies');
CALL create_rls_policy('company_settings');
CALL create_rls_policy('products');
CALL create_rls_policy('product_variants');
CALL create_rls_policy('orders');
CALL create_rls_policy('order_line_items');
CALL create_rls_policy('customers');
CALL create_rls_policy('suppliers');
CALL create_rls_policy('integrations');
CALL create_rls_policy('inventory_ledger');
CALL create_rls_policy('channel_fees');
CALL create_rls_policy('discounts');
CALL create_rls_policy('refunds');
CALL create_rls_policy('refund_line_items');
CALL create_rls_policy('export_jobs');
CALL create_rls_policy('conversations');
CALL create_rls_policy('messages');
CALL create_rls_policy('audit_log');


-- Function to record an order from a platform payload
CREATE OR REPLACE FUNCTION public.record_order_from_platform(
    p_company_id UUID,
    p_platform TEXT,
    p_order_payload JSONB
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_order_id UUID;
    v_customer_id UUID;
    v_line_item JSONB;
    v_variant_id UUID;
    v_product_id UUID;
BEGIN
    -- This function is a placeholder and should be adapted for each platform's payload structure.
    -- The example below is a simplified structure.
    -- Find or create the customer
    -- ...

    -- Create the order
    INSERT INTO public.orders (company_id, order_number, total_amount, source_platform, external_order_id, created_at)
    VALUES (
        p_company_id,
        p_order_payload ->> 'order_number',
        (p_order_payload ->> 'total_price')::numeric * 100,
        p_platform,
        p_order_payload ->> 'id',
        (p_order_payload ->> 'created_at')::timestamptz
    )
    RETURNING id INTO v_order_id;

    -- Process line items
    FOR v_line_item IN SELECT * FROM jsonb_array_elements(p_order_payload -> 'line_items')
    LOOP
        -- Find the corresponding product variant
        SELECT pv.id, pv.product_id INTO v_variant_id, v_product_id
        FROM public.product_variants pv
        WHERE pv.company_id = p_company_id
        AND pv.external_variant_id = v_line_item ->> 'variant_id';

        -- Insert the line item
        INSERT INTO public.order_line_items (order_id, company_id, variant_id, product_id, product_name, sku, quantity, price)
        VALUES (
            v_order_id,
            p_company_id,
            v_variant_id,
            v_product_id,
            v_line_item ->> 'title',
            v_line_item ->> 'sku',
            (v_line_item ->> 'quantity')::int,
            (v_line_item ->> 'price')::numeric * 100
        );

        -- Update inventory ledger if a variant was found
        IF v_variant_id IS NOT NULL THEN
            INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id)
            SELECT
                p_company_id,
                v_variant_id,
                'sale',
                -( (v_line_item ->> 'quantity')::int ),
                pv.inventory_quantity - (v_line_item ->> 'quantity')::int,
                v_order_id
            FROM public.product_variants pv
            WHERE pv.id = v_variant_id;
        END IF;

    END LOOP;
END;
$$;
