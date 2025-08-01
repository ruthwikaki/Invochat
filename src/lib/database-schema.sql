-- ============================================================================
-- IDEMPOTENT AUTH FUNCTION MIGRATION
-- ============================================================================
-- This script safely replaces a problematic SQL function by temporarily
-- disabling Row-Level Security, dropping the old function, creating the
-- new correct version, and then re-enabling RLS. This resolves
-- dependency errors and the "infinite recursion" bug.

-- Use a transaction to ensure all or nothing completes.
BEGIN;

-- Lock tables to prevent concurrent modifications during the migration.
LOCK TABLE
    public.products,
    public.product_variants,
    public.orders,
    public.order_line_items,
    public.customers,
    public.suppliers,
    public.purchase_orders,
    public.purchase_order_line_items,
    public.integrations,
    public.webhook_events,
    public.inventory_ledger,
    public.messages,
    public.audit_log,
    public.company_settings,
    public.refunds,
    public.channel_fees,
    public.feedback,
    public.export_jobs,
    public.company_users
IN ACCESS EXCLUSIVE MODE;

-- Temporarily disable RLS on all tables that depend on the function.
ALTER TABLE public.products DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users DISABLE ROW LEVEL SECURITY;

-- Drop the old function now that dependencies are removed.
DROP FUNCTION IF EXISTS public.get_company_id_for_user(p_user_id uuid);

-- Create the new, correct function that gets the company_id from the JWT.
-- This function takes no arguments and uses the security invoker context.
CREATE OR REPLACE FUNCTION public.get_my_company_id()
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER -- Important: Runs as the calling user to access their JWT
STABLE
AS $$
BEGIN
  -- This reliably gets the company_id from the user's session token,
  -- breaking the recursive dependency loop.
  RETURN NULLIF(auth.jwt()->'app_metadata'->>'company_id', '')::uuid;
END;
$$;

-- Grant execute permissions to authenticated users.
GRANT EXECUTE ON FUNCTION public.get_my_company_id() TO authenticated;

-- Recreate all RLS policies to use the new function `get_my_company_id()`.

-- Products
DROP POLICY IF EXISTS "User can access their own company data" ON public.products;
CREATE POLICY "User can access their own company data" ON public.products
  FOR ALL USING (company_id = public.get_my_company_id());

-- Product Variants
DROP POLICY IF EXISTS "User can access their own company data" ON public.product_variants;
CREATE POLICY "User can access their own company data" ON public.product_variants
  FOR ALL USING (company_id = public.get_my_company_id());

-- Orders
DROP POLICY IF EXISTS "User can access their own company data" ON public.orders;
CREATE POLICY "User can access their own company data" ON public.orders
  FOR ALL USING (company_id = public.get_my_company_id());
  
-- Order Line Items
DROP POLICY IF EXISTS "User can access their own company data" ON public.order_line_items;
CREATE POLICY "User can access their own company data" ON public.order_line_items
  FOR ALL USING (company_id = public.get_my_company_id());

-- Customers
DROP POLICY IF EXISTS "User can access their own company data" ON public.customers;
CREATE POLICY "User can access their own company data" ON public.customers
  FOR ALL USING (company_id = public.get_my_company_id());

-- Suppliers
DROP POLICY IF EXISTS "User can access their own company data" ON public.suppliers;
CREATE POLICY "User can access their own company data" ON public.suppliers
  FOR ALL USING (company_id = public.get_my_company_id());

-- Purchase Orders
DROP POLICY IF EXISTS "User can access their own company data" ON public.purchase_orders;
CREATE POLICY "User can access their own company data" ON public.purchase_orders
  FOR ALL USING (company_id = public.get_my_company_id());

-- Purchase Order Line Items
DROP POLICY IF EXISTS "User can access their own company data" ON public.purchase_order_line_items;
CREATE POLICY "User can access their own company data" ON public.purchase_order_line_items
  FOR ALL USING (company_id = public.get_my_company_id());

-- Integrations
DROP POLICY IF EXISTS "User can access their own company data" ON public.integrations;
CREATE POLICY "User can access their own company data" ON public.integrations
  FOR ALL USING (company_id = public.get_my_company_id());

-- Webhook Events
DROP POLICY IF EXISTS "User can access their own company data" ON public.webhook_events;
CREATE POLICY "User can access their own company data" ON public.webhook_events
  FOR ALL USING (company_id = (SELECT company_id FROM integrations WHERE id = integration_id AND company_id = public.get_my_company_id()));

-- Inventory Ledger
DROP POLICY IF EXISTS "User can access their own company data" ON public.inventory_ledger;
CREATE POLICY "User can access their own company data" ON public.inventory_ledger
  FOR ALL USING (company_id = public.get_my_company_id());

-- Messages
DROP POLICY IF EXISTS "Allow access to own messages" ON public.messages;
CREATE POLICY "Allow access to own messages" ON public.messages
  FOR ALL USING (company_id = public.get_my_company_id());

-- Audit Log
DROP POLICY IF EXISTS "Allow admins and owners to read logs" ON public.audit_log;
CREATE POLICY "Allow admins and owners to read logs" ON public.audit_log
  FOR SELECT USING (company_id = public.get_my_company_id());

-- Company Settings
DROP POLICY IF EXISTS "User can access their own company settings" ON public.company_settings;
CREATE POLICY "User can access their own company settings" ON public.company_settings
  FOR ALL USING (company_id = public.get_my_company_id());
  
-- Refunds
DROP POLICY IF EXISTS "Allow full access to own company data" ON public.refunds;
CREATE POLICY "Allow full access to own company data" ON public.refunds
  FOR ALL USING (company_id = public.get_my_company_id());

-- Channel Fees
DROP POLICY IF EXISTS "Allow full access to own company data" ON public.channel_fees;
CREATE POLICY "Allow full access to own company data" ON public.channel_fees
  FOR ALL USING (company_id = public.get_my_company_id());

-- Feedback
DROP POLICY IF EXISTS "Allow access to own company feedback" ON public.feedback;
CREATE POLICY "Allow access to own company feedback" ON public.feedback
  FOR ALL USING (company_id = public.get_my_company_id());

-- Export Jobs
DROP POLICY IF EXISTS "Allow access to own company export jobs" ON public.export_jobs;
CREATE POLICY "Allow access to own company export jobs" ON public.export_jobs
  FOR ALL USING (company_id = public.get_my_company_id());

-- Company Users
DROP POLICY IF EXISTS "Enable read access for company members" ON public.company_users;
CREATE POLICY "Enable read access for company members" ON public.company_users
  FOR SELECT USING (company_id = public.get_my_company_id());

-- Re-enable RLS on all tables.
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;

COMMIT;

RAISE NOTICE 'Auth function migration completed successfully.';
