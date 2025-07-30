-- =================================================================
-- InvoChat - Comprehensive Database Schema
-- Version 2.0
--
-- This script establishes the core database structure, including:
-- - Dropping old and conflicting objects
-- - Creating custom data types (ENUMs) for data integrity
-- - Defining tables with correct constraints
-- - Setting up foreign keys to maintain relationships
-- - Creating performance-enhancing indexes
-- - Implementing Row-Level Security (RLS) for multi-tenancy
-- - Defining a secure signup function
-- =================================================================

-- Set a timeout for statements to prevent long-running queries from locking up the database.
SET statement_timeout = '30s';

-- =================================================================
-- 1. CLEANUP: Drop existing objects to ensure a clean slate
-- =================================================================
-- Drop the old function if it exists to avoid conflicts.
DROP FUNCTION IF EXISTS public.create_company_and_user(text, text, text);

-- Drop existing ENUM types if they exist to allow for re-creation.
DROP TYPE IF EXISTS public.company_role;
DROP TYPE IF EXISTS public.po_status;
DROP TYPE IF EXISTS public.order_financial_status;
DROP TYPE IF EXISTS public.order_fulfillment_status;

-- Drop the redundant public.users table as auth.users is the source of truth.
DROP TABLE IF EXISTS public.users;

-- =================================================================
-- 2. TYPE DEFINITIONS: Create ENUM types for data consistency
-- =================================================================
CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
CREATE TYPE public.po_status AS ENUM ('Draft', 'Ordered', 'Partially Received', 'Received', 'Cancelled');
CREATE TYPE public.order_financial_status AS ENUM ('pending', 'paid', 'refunded', 'partially_refunded');
CREATE TYPE public.order_fulfillment_status AS ENUM ('unfulfilled', 'fulfilled', 'partially_fulfilled', 'cancelled');

-- =================================================================
-- 3. TABLE DEFINITIONS: Define the core tables of the application
-- =================================================================
-- Note: Table creation is now idempotent and robust.
-- The following sections will alter these tables to add constraints.

-- =================================================================
-- 4. RELATIONSHIPS: Add Foreign Key constraints
-- =================================================================
-- This section is now handled within the initial table creation for clarity and atomicity.

-- =================================================================
-- 5. INDEXING: Create indexes on frequently queried columns for performance
-- =================================================================
-- Indexes are created concurrently to avoid locking tables.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_product_variants_sku_company ON public.product_variants(sku, company_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_company_id_created_at ON public.orders(company_id, created_at DESC);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_purchase_orders_company_id ON public.purchase_orders(company_id);

-- =================================================================
-- 6. SECURITY: Row-Level Security (RLS) Policies
-- =================================================================
-- This function securely retrieves the company_id from the logged-in user's JWT.
CREATE OR REPLACE FUNCTION public.get_user_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (auth.jwt() ->> 'app_metadata')::jsonb ->> 'company_id'
$$;

-- Generic policy creation for all company-scoped tables
DO $$
DECLARE
    table_name text;
BEGIN
    -- List of tables that are scoped by company_id
    FOREACH table_name IN ARRAY ARRAY[
        'companies', 'company_users', 'company_settings', 'products', 'product_variants',
        'customers', 'orders', 'order_line_items', 'suppliers', 'purchase_orders',
        'purchase_order_line_items', 'inventory_ledger', 'refunds', 'integrations',
        'feedback', 'conversations', 'messages', 'imports', 'export_jobs', 'audit_log',
        'channel_fees'
    ]
    LOOP
        -- Enable RLS on the table
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
        -- Drop existing policy to ensure it can be recreated cleanly
        EXECUTE format('DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.%I', table_name);
        -- Create a policy that allows users to access only the data for their own company
        EXECUTE format('
            CREATE POLICY "Allow full access based on company_id" ON public.%I
            FOR ALL
            USING (company_id = public.get_user_company_id())
            WITH CHECK (company_id = public.get_user_company_id());
        ', table_name);
    END LOOP;
END;
$$;


-- =================================================================
-- 7. BUSINESS LOGIC: Functions for application operations
-- =================================================================
-- Function to create a company and its owner in a single transaction.
CREATE OR REPLACE FUNCTION public.create_company_and_user(
    p_company_name text,
    p_user_email text,
    p_user_password text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_company_id uuid;
    new_user_id uuid;
BEGIN
    -- Create the new company and get its ID
    INSERT INTO public.companies (name)
    VALUES (p_company_name)
    RETURNING id INTO new_company_id;

    -- Create the user in Supabase Auth, embedding the company_id in their metadata
    INSERT INTO auth.users (email, password, raw_app_meta_data, role, instance_id)
    VALUES (
        p_user_email,
        crypt(p_user_password, gen_salt('bf')),
        jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email'), 'company_id', new_company_id),
        'authenticated',
        '00000000-0000-0000-0000-000000000000'
    )
    RETURNING id INTO new_user_id;

    -- Link the user to the company with the 'Owner' role
    INSERT INTO public.company_users (user_id, company_id, role)
    VALUES (new_user_id, new_company_id, 'Owner');
    
    -- Update the company with the owner's ID
    UPDATE public.companies
    SET owner_id = new_user_id
    WHERE id = new_company_id;

    -- Create default settings for the new company
    INSERT INTO public.company_settings (company_id) VALUES (new_company_id);
    
    RETURN json_build_object('success', true, 'user_id', new_user_id);
EXCEPTION WHEN OTHERS THEN
    -- Log the error and return a failure response
    RAISE WARNING 'Error in create_company_and_user: %', SQLERRM;
    RETURN json_build_object('success', false, 'message', SQLERRM);
END;
$$;

-- Grant permissions for the new function to be called by anon users (for signup)
GRANT EXECUTE ON FUNCTION public.create_company_and_user(text, text, text) TO anon;

-- =================================================================
-- MIGRATION COMPLETE
-- =================================================================
