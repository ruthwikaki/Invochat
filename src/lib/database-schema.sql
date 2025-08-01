-- ============================================================================
-- FINAL AUTHENTICATION AND RLS FIX SCRIPT
-- ============================================================================
-- This script safely replaces a faulty function by temporarily disabling
-- dependent policies, replacing the function, and then recreating the policies.
-- It is idempotent and safe to run on a partially migrated database.

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
    public.company_users,
    public.feedback,
    public.export_jobs,
    public.channel_fees,
    public.refunds
IN EXCLUSIVE MODE;

-- Step 1: Temporarily drop all policies that depend on the function.
-- This is necessary because we cannot replace the function while objects depend on it.
DO $$
DECLARE
    policy_record RECORD;
    policy_definitions TEXT[];
    i INT;
BEGIN
    -- Store policy definitions before dropping them
    SELECT array_agg(pg_get_policydef(p.oid))
    INTO policy_definitions
    FROM pg_policy p
    LEFT JOIN pg_class c ON c.oid = p.polrelid
    LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND (
        pg_get_expr(p.polqual, p.polrelid) ILIKE '%get_company_id_for_user%' OR
        pg_get_expr(p.polwithcheck, p.polrelid) ILIKE '%get_company_id_for_user%'
      );

    -- Drop the policies
    FOR policy_record IN
        SELECT
            'ALTER TABLE ' || quote_ident(schemaname) || '.' || quote_ident(tablename) ||
            ' DROP POLICY IF EXISTS ' || quote_ident(policyname) || ';' AS drop_command
        FROM
            pg_policies
        WHERE
            schemaname = 'public'
            AND (qual ILIKE '%get_company_id_for_user%' OR with_check ILIKE '%get_company_id_for_user%')
    LOOP
        EXECUTE policy_record.drop_command;
    END LOOP;

    -- Step 2: Drop the old function
    DROP FUNCTION IF EXISTS public.get_company_id_for_user(uuid);

    -- Step 3: Recreate the function with the corrected logic
    CREATE OR REPLACE FUNCTION public.get_company_id_for_user()
    RETURNS uuid
    LANGUAGE sql
    SECURITY DEFINER
    STABLE
    AS $$
      SELECT NULLIF(current_setting('request.jwt.claims', true)::jsonb->'app_metadata'->>'company_id', '')::uuid;
    $$;

    -- Step 4: Recreate the policies from their stored definitions
    IF policy_definitions IS NOT NULL THEN
        FOR i IN 1..array_length(policy_definitions, 1)
        LOOP
            EXECUTE policy_definitions[i];
        END LOOP;
    END IF;

END;
$$;


-- ============================================================================
-- STEP 2: FIX and HARDEN the handle_new_user trigger
-- ============================================================================
-- This ensures that new user signups are handled robustly.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  company_id_to_set UUID;
  sanitized_company_name TEXT;
BEGIN
  -- Sanitize and validate the company name from the user metadata
  sanitized_company_name := btrim(new.raw_user_meta_data->>'company_name');

  -- If the sanitized name is empty or null, create a fallback name
  IF sanitized_company_name IS NULL OR sanitized_company_name = '' THEN
    sanitized_company_name := 'Company for ' || new.email;
  END IF;

  -- Limit the length to prevent abuse
  sanitized_company_name := left(sanitized_company_name, 100);

  -- Create the company with the user as the owner
  INSERT INTO public.companies (name, owner_id)
  VALUES (sanitized_company_name, new.id)
  RETURNING id INTO company_id_to_set;

  -- Add the user to the company_users table as an Owner
  INSERT INTO public.company_users (company_id, user_id, role)
  VALUES (company_id_to_set, new.id, 'Owner');

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id_to_set)
  WHERE id = new.id;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Ensure the trigger is correctly attached to the auth.users table
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


COMMIT;
