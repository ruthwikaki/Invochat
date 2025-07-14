-- InvoChat Database Schema
-- Version: 1.5.0
-- Description: Adds locations table and links it to variants and ledger.

-- Drop existing functions and triggers if they exist to ensure idempotency.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.get_current_company_id();
DROP FUNCTION IF EXISTS public.set_updated_at();
DROP FUNCTION IF EXISTS public.apply_updated_at_trigger(text);
DROP FUNCTION IF EXISTS public.get_user_role();


-- Enable the pg_cron extension for scheduled jobs.
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

-- Create a function to securely get the company_id from the JWT.
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS UUID AS $$
BEGIN
  RETURN (current_setting('request.jwt.claims', true)::jsonb ->> 'company_id')::UUID;
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create a function to get the user's role from the JWT.
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS TEXT AS $$
BEGIN
  RETURN current_setting('request.jwt.claims', true)::jsonb ->> 'role';
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Enable Row-Level Security (RLS) for all tables by default.
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;

-- Drop existing policies before creating new ones.
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.companies;
DROP POLICY IF EXISTS "Users can see other users in their own company." ON auth.users;
DROP POLICY IF EXISTS "Allow read access to other users in same company" ON public.users;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.company_settings;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.products;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.product_variants;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.inventory_ledger;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.customers;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.orders;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.order_line_items;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.suppliers;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.integrations;
DROP POLICY IF EXISTS "Allow full access to own conversations" ON public.conversations;
DROP POLICY IF EXISTS "Allow full access to messages in own conversations" ON public.messages;
DROP POLICY IF EXISTS "Allow read access to company audit log" ON public.audit_log;
DROP POLICY IF EXISTS "Allow read access to webhook_events" ON public.webhook_events;
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.locations;

-- RLS Policies
-- Users can only see their own company.
CREATE POLICY "Allow full access based on company_id"
ON public.companies
FOR ALL
USING (id = get_current_company_id())
WITH CHECK (id = get_current_company_id());

-- Users can see other users in their own company.
CREATE POLICY "Users can see other users in their own company."
ON auth.users FOR SELECT
USING (get_current_company_id() = (raw_user_meta_data ->> 'company_id')::uuid);

-- Users can read profiles of other users in the same company
CREATE POLICY "Allow read access to other users in same company"
ON public.users FOR SELECT
USING (company_id = get_current_company_id());


-- Generic policy for tables with a company_id column.
CREATE POLICY "Allow full access based on company_id" ON public.company_settings FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.products FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.product_variants FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.inventory_ledger FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.customers FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.orders FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.order_line_items FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.suppliers FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.integrations FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access based on company_id" ON public.locations FOR ALL USING (company_id = get_current_company_id());


-- Policies for chat functionality
CREATE POLICY "Allow full access to own conversations" ON public.conversations FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Allow full access to messages in own conversations" ON public.messages FOR ALL USING (company_id = get_current_company_id());

-- Policies for logging and events
CREATE POLICY "Allow read access to company audit log" ON public.audit_log FOR SELECT USING (company_id = get_current_company_id());
CREATE POLICY "Allow read access to webhook_events" ON public.webhook_events FOR ALL USING (
    (get_user_role() = 'Admin') AND
    integration_id IN (
        SELECT id FROM public.integrations WHERE company_id = get_current_company_id()
    )
);


-- Function to handle new user creation.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  new_company_id UUID;
  user_meta jsonb;
BEGIN
  -- Extract metadata from the new user record
  user_meta := new.raw_user_meta_data;

  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (user_meta ->> 'company_name')
  RETURNING id INTO new_company_id;

  -- Create a corresponding user profile
  INSERT INTO public.users (id, email, company_id, role)
  VALUES (new.id, new.email, new_company_id, 'Owner');
  
  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = jsonb_set(
      COALESCE(raw_app_meta_data, '{}'::jsonb),
      '{company_id}',
      to_jsonb(new_company_id)
  )
  WHERE id = new.id;
  
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Trigger to execute the handle_new_user function on new user signup.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
  

-- Function to automatically set the updated_at timestamp on row update.
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = (now() at time zone 'utc');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Helper function to apply the updated_at trigger to a table.
CREATE OR REPLACE FUNCTION public.apply_updated_at_trigger(table_name_param text)
RETURNS void AS $$
BEGIN
    EXECUTE format('
        CREATE TRIGGER handle_updated_at
        BEFORE UPDATE ON public.%I
        FOR EACH ROW
        EXECUTE FUNCTION public.set_updated_at();
    ', table_name_param);
END;
$$ LANGUAGE plpgsql;

-- Apply the trigger to all tables that have an updated_at column.
SELECT public.apply_updated_at_trigger(table_name)
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE' AND table_name IN (
    'companies', 'company_settings', 'products', 'product_variants', 'customers',
    'orders', 'suppliers', 'conversations', 'integrations'
);

-- Function to run periodic cleanup jobs.
CREATE OR REPLACE FUNCTION public.cleanup_old_data()
RETURNS void AS $$
BEGIN
    -- Delete audit logs older than 90 days
    DELETE FROM public.audit_log WHERE created_at < now() - interval '90 days';
    
    -- Delete webhook events older than 30 days
    DELETE FROM public.webhook_events WHERE received_at < now() - interval '30 days';

    -- Delete non-starred conversations and their messages older than 180 days
    DELETE FROM public.messages m
    USING public.conversations c
    WHERE m.conversation_id = c.id
      AND c.is_starred = false
      AND c.last_accessed_at < now() - interval '180 days';
      
    DELETE FROM public.conversations
    WHERE is_starred = false
      AND last_accessed_at < now() - interval '180 days';
      
END;
$$ LANGUAGE plpgsql;

-- Schedule the cleanup job to run daily at 3 AM UTC.
SELECT cron.schedule('daily-cleanup', '0 3 * * *', 'SELECT public.cleanup_old_data()');


-- Final table and view definitions
-- Note: All tables are created in the public schema by default.

CREATE TABLE IF NOT EXISTS public.locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    address TEXT,
    is_default BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updated_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_locations_company_id ON public.locations(company_id);

ALTER TABLE public.product_variants
    ADD COLUMN IF NOT EXISTS location_id UUID REFERENCES public.locations(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_product_variants_location_id ON public.product_variants(location_id);

ALTER TABLE public.inventory_ledger
    ADD COLUMN IF NOT EXISTS location_id UUID REFERENCES public.locations(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_location_id ON public.inventory_ledger(location_id);


-- Create the product variants view
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    pv.company_id,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type,
    pv.sku,
    pv.title,
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
    pv.inventory_quantity AS quantity, -- Alias for consistency
    pv.inventory_quantity, -- Keep original for direct access
    pv.external_variant_id,
    pv.location_id,
    l.name AS location_name,
    pv.created_at,
    pv.updated_at
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id
LEFT JOIN
    public.locations l ON pv.location_id = l.id;


-- Add missing foreign key indexes
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);

-- Add GIN index for product tags for faster array searching
CREATE INDEX IF NOT EXISTS idx_products_tags_gin ON public.products USING GIN (tags);

-- Add indexes for foreign keys to improve join performance
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations(company_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_company_user ON public.audit_log(company_id, user_id);
CREATE INDEX IF NOT EXISTS idx_webhook_events_integration_id ON public.webhook_events(integration_id);


-- Set ownership of schema and objects to the postgres role for consistency.
ALTER SCHEMA public OWNER TO postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO anon;
GRANT ALL ON SCHEMA public TO authenticated;
GRANT ALL ON SCHEMA public TO service_role;
ALTER FUNCTION public.handle_new_user() OWNER TO postgres;
ALTER FUNCTION public.get_current_company_id() OWNER TO postgres;
ALTER FUNCTION public.set_updated_at() OWNER TO postgres;
ALTER FUNCTION public.apply_updated_at_trigger(text) OWNER TO postgres;
ALTER FUNCTION public.cleanup_old_data() OWNER TO postgres;
ALTER FUNCTION public.get_user_role() OWNER TO postgres;
ALTER VIEW public.product_variants_with_details OWNER TO postgres;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA extensions TO postgres, anon, authenticated, service_role;

-- Revoke execute on cron functions from anon and authenticated roles for security.
REVOKE EXECUTE ON FUNCTION extensions.schedule(text, text, text) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION extensions.unschedule(text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION extensions.schedule(text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION extensions.unschedule(text) TO service_role;
GRANT USAGE ON SCHEMA cron TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA cron TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA cron TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA cron TO service_role;

-- Final RLS policies for auth tables
ALTER TABLE auth.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth.sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow user to see their own session" ON auth.sessions;
CREATE POLICY "Allow user to see their own session" ON auth.sessions FOR SELECT USING (user_id = auth.uid());
