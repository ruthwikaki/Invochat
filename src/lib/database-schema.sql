-- =====================================
-- TAILORED MIGRATION SCRIPT FOR YOUR DATABASE
-- Run this in Supabase SQL Editor
-- =====================================

BEGIN;

-- Step 1: Check current state
DO $$
BEGIN
    RAISE NOTICE 'Starting migration for database with % tables', (
        SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public'
    );
END $$;

-- Step 2: Drop ALL existing RLS policies that might cause recursion
DO $$
DECLARE
    r RECORD;
BEGIN
    -- Drop all policies on company_users table
    FOR r IN SELECT policyname FROM pg_policies WHERE tablename = 'company_users' 
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON company_users', r.policyname);
        RAISE NOTICE 'Dropped policy: %', r.policyname;
    END LOOP;
    
    -- Drop all policies on companies table
    FOR r IN SELECT policyname FROM pg_policies WHERE tablename = 'companies' 
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON companies', r.policyname);
        RAISE NOTICE 'Dropped policy: %', r.policyname;
    END LOOP;
END $$;

-- Step 3: Create the JWT refresh function
CREATE OR REPLACE FUNCTION refresh_user_jwt_metadata(user_uuid uuid)
RETURNS void AS $$
DECLARE
    company_uuid uuid;
BEGIN
    -- Get the user's company ID from company_users table
    SELECT company_id INTO company_uuid
    FROM company_users 
    WHERE user_id = user_uuid
    LIMIT 1;
    
    IF company_uuid IS NOT NULL THEN
        -- Update the user's JWT metadata in auth.users
        UPDATE auth.users 
        SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || 
            jsonb_build_object('company_id', company_uuid)
        WHERE id = user_uuid;
        
        RAISE NOTICE 'Updated JWT for user % with company %', user_uuid, company_uuid;
    ELSE
        RAISE NOTICE 'No company found for user %', user_uuid;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 4: Fix ALL existing users who are missing company_id in JWT
DO $$
DECLARE
    user_record RECORD;
    updated_count INTEGER := 0;
BEGIN
    FOR user_record IN 
        SELECT u.id, u.email, cu.company_id
        FROM auth.users u
        JOIN company_users cu ON u.id = cu.user_id
        WHERE (u.raw_app_meta_data->>'company_id' IS NULL OR u.raw_app_meta_data IS NULL)
    LOOP
        UPDATE auth.users 
        SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || 
            jsonb_build_object('company_id', user_record.company_id)
        WHERE id = user_record.id;
        
        updated_count := updated_count + 1;
        RAISE NOTICE 'Fixed JWT for user % (%) with company %', 
            user_record.email, user_record.id, user_record.company_id;
    END LOOP;
    
    RAISE NOTICE 'Updated JWT metadata for % existing users', updated_count;
END $$;

-- Step 5: Update the handle_new_user trigger function
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Create company first
  INSERT INTO public.companies (name, owner_id)
  VALUES (
    COALESCE(NEW.raw_user_meta_data->>'company_name', 'My Company'),
    NEW.id
  )
  RETURNING id INTO new_company_id;
  
  -- Create company_users association with proper role
  INSERT INTO public.company_users (company_id, user_id, role)
  VALUES (new_company_id, NEW.id, 'Owner');
  
  -- CRITICAL: Update JWT metadata immediately to prevent race conditions
  UPDATE auth.users 
  SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || 
    jsonb_build_object('company_id', new_company_id)
  WHERE id = NEW.id;
  
  RAISE NOTICE 'Created company % for new user %', new_company_id, NEW.id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Ensure the trigger exists
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Step 6: Enable RLS on tables (if not already enabled)
ALTER TABLE company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_line_items ENABLE ROW LEVEL SECURITY;

-- Step 7: Create simple, non-recursive RLS policies

-- Policy for company_users: Users can only see their own association
CREATE POLICY "company_users_select_own" ON company_users
    FOR SELECT
    USING (auth.uid() = user_id);

-- Policy for companies: Users can see companies they own or are members of
CREATE POLICY "companies_select_accessible" ON companies
    FOR SELECT
    USING (
        auth.uid() = owner_id 
        OR 
        EXISTS (
            SELECT 1 FROM company_users cu 
            WHERE cu.company_id = companies.id 
            AND cu.user_id = auth.uid()
        )
    );

-- JWT-based policies for main tables (no database recursion)
CREATE POLICY "products_company_access" ON products
    FOR ALL
    USING ((auth.jwt() ->> 'company_id')::uuid = company_id)
    WITH CHECK ((auth.jwt() ->> 'company_id')::uuid = company_id);

CREATE POLICY "orders_company_access" ON orders
    FOR ALL
    USING ((auth.jwt() ->> 'company_id')::uuid = company_id)
    WITH CHECK ((auth.jwt() ->> 'company_id')::uuid = company_id);

CREATE POLICY "customers_company_access" ON customers
    FOR ALL
    USING ((auth.jwt() ->> 'company_id')::uuid = company_id)
    WITH CHECK ((auth.jwt() ->> 'company_id')::uuid = company_id);

CREATE POLICY "product_variants_company_access" ON product_variants
    FOR ALL
    USING ((auth.jwt() ->> 'company_id')::uuid = company_id)
    WITH CHECK ((auth.jwt() ->> 'company_id')::uuid = company_id);

CREATE POLICY "order_line_items_company_access" ON order_line_items
    FOR ALL
    USING ((auth.jwt() ->> 'company_id')::uuid = company_id)
    WITH CHECK ((auth.jwt() ->> 'company_id')::uuid = company_id);

CREATE POLICY "suppliers_company_access" ON suppliers
    FOR ALL
    USING ((auth.jwt() ->> 'company_id')::uuid = company_id)
    WITH CHECK ((auth.jwt() ->> 'company_id')::uuid = company_id);

CREATE POLICY "purchase_orders_company_access" ON purchase_orders
    FOR ALL
    USING ((auth.jwt() ->> 'company_id')::uuid = company_id)
    WITH CHECK ((auth.jwt() ->> 'company_id')::uuid = company_id);

CREATE POLICY "company_settings_company_access" ON company_settings
    FOR ALL
    USING ((auth.jwt() ->> 'company_id')::uuid = company_id)
    WITH CHECK ((auth.jwt() ->> 'company_id')::uuid = company_id);

-- Step 8: Grant proper permissions
GRANT SELECT ON company_users TO authenticated;
GRANT SELECT ON companies TO authenticated;
GRANT ALL ON products TO authenticated;
GRANT ALL ON orders TO authenticated;
GRANT ALL ON customers TO authenticated;
GRANT ALL ON product_variants TO authenticated;
GRANT ALL ON order_line_items TO authenticated;
GRANT ALL ON suppliers TO authenticated;
GRANT ALL ON purchase_orders TO authenticated;
GRANT ALL ON company_settings TO authenticated;

-- Grant full access to service role
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;

-- Step 9: Create performance indexes
CREATE INDEX IF NOT EXISTS idx_company_users_user_id ON company_users(user_id);
CREATE INDEX IF NOT EXISTS idx_company_users_company_id ON company_users(company_id);
CREATE INDEX IF NOT EXISTS idx_companies_owner_id ON companies(owner_id);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON products(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON orders(company_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON customers(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_company_id ON order_line_items(company_id);

-- Step 10: Verify the migration worked
DO $$
DECLARE
    total_users INTEGER;
    users_with_jwt INTEGER;
    policies_count INTEGER;
BEGIN
    -- Count total users
    SELECT COUNT(*) INTO total_users FROM auth.users;
    
    -- Count users with proper JWT metadata
    SELECT COUNT(*) INTO users_with_jwt 
    FROM auth.users u
    JOIN company_users cu ON u.id = cu.user_id
    WHERE u.raw_app_meta_data->>'company_id' = cu.company_id::text;
    
    -- Count active policies
    SELECT COUNT(*) INTO policies_count 
    FROM pg_policies 
    WHERE tablename IN ('company_users', 'companies', 'products', 'orders', 'customers');
    
    RAISE NOTICE '=== MIGRATION COMPLETE ===';
    RAISE NOTICE 'Total users: %', total_users;
    RAISE NOTICE 'Users with correct JWT: %', users_with_jwt;
    RAISE NOTICE 'Active RLS policies: %', policies_count;
    
    IF users_with_jwt = total_users THEN
        RAISE NOTICE '✅ All users have correct JWT metadata';
    ELSE
        RAISE WARNING '⚠️  Some users may still need JWT fixes';
    END IF;
END $$;

COMMIT;

-- Final verification query - run this separately to check results
SELECT 
    u.id,
    u.email,
    u.raw_app_meta_data->>'company_id' as jwt_company_id,
    cu.company_id::text as db_company_id,
    CASE 
        WHEN u.raw_app_meta_data->>'company_id' = cu.company_id::text THEN '✅ Match'
        ELSE '❌ Mismatch'
    END as status
FROM auth.users u
LEFT JOIN company_users cu ON u.id = cu.user_id
ORDER BY u.created_at DESC
LIMIT 10;
