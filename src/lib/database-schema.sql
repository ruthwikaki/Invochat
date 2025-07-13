-- =================================================================
-- InvoChat - Non-Destructive Database Migration Script
-- Version: 2.0
-- Description: This script migrates the database from the initial
--              simple schema to the full multi-tenant SaaS schema.
--              It is designed to be idempotent and preserve existing data
--              by altering tables and migrating data where possible.
-- =================================================================

-- Lock the tables to prevent concurrent modifications during migration.
LOCK TABLE public.inventory, public.sales, public.customers IN EXCLUSIVE MODE;

-- =================================================================
-- Step 1: Rename Existing Tables to Preserve Data
-- =================================================================
-- We rename the old `inventory` table to `products`.
DO $$
BEGIN
   IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'inventory') AND
      NOT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'products') THEN
      ALTER TABLE public.inventory RENAME TO products;
      RAISE NOTICE 'Table "inventory" renamed to "products".';
   END IF;
END $$;

-- We rename the old `sales` table to `orders`.
DO $$
BEGIN
   IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sales') AND
      NOT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'orders') THEN
      ALTER TABLE public.sales RENAME TO orders;
      RAISE NOTICE 'Table "sales" renamed to "orders".';
   END IF;
END $$;


-- =================================================================
-- Step 2: Create New Tables
-- =================================================================
-- This is the new table for product variations (e.g., Small, Medium, Large).
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id uuid NOT NULL, -- Constraint added later
    company_id uuid NOT NULL, -- Constraint added later
    sku text NOT NULL,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price integer, -- Price in cents
    compare_at_price integer,
    cost integer, -- Cost in cents
    inventory_quantity integer DEFAULT 0,
    external_variant_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone
);
RAISE NOTICE 'Table "product_variants" created or already exists.';

-- This table will store the items associated with each order.
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL, -- Constraint added later
    company_id uuid NOT NULL,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    product_name text NOT NULL,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL, -- Price in cents
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    cost_at_time integer,
    external_line_item_id text
);
RAISE NOTICE 'Table "order_line_items" created or already exists.';


-- =================================================================
-- Step 3: Alter Existing Tables to Match New Schema
-- =================================================================

-- Alter the renamed `products` table
ALTER TABLE public.products
    RENAME COLUMN name TO title,
    RENAME COLUMN category TO product_type,
    ADD COLUMN IF NOT EXISTS handle text,
    ADD COLUMN IF NOT EXISTS description text,
    ADD COLUMN IF NOT EXISTS tags text[],
    ADD COLUMN IF NOT EXISTS status text,
    ADD COLUMN IF NOT EXISTS image_url text,
    DROP COLUMN IF EXISTS sku,
    DROP COLUMN IF EXISTS quantity,
    DROP COLUMN IF EXISTS price,
    DROP COLUMN IF EXISTS cost,
    DROP COLUMN IF EXISTS reorder_point,
    DROP COLUMN IF EXISTS last_sold_date,
    DROP COLUMN IF EXISTS barcode,
    DROP COLUMN IF EXISTS version,
    DROP COLUMN IF EXISTS deleted_by,
    DROP COLUMN IF EXISTS external_quantity,
    DROP COLUMN IF EXISTS supplier_id,
    DROP COLUMN IF EXISTS reorder_quantity,
    DROP COLUMN IF EXISTS lead_time_days;
RAISE NOTICE 'Table "products" altered successfully.';

-- Alter the renamed `orders` table
ALTER TABLE public.orders
    RENAME COLUMN sale_number TO order_number,
    RENAME COLUMN total_amount TO total_amount_numeric,
    ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'completed',
    ADD COLUMN IF NOT EXISTS financial_status text DEFAULT 'paid',
    ADD COLUMN IF NOT EXISTS fulfillment_status text DEFAULT 'fulfilled',
    ADD COLUMN IF NOT EXISTS currency text DEFAULT 'USD',
    ADD COLUMN IF NOT EXISTS subtotal integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS total_tax integer DEFAULT 0,
    ADD COLUMN IF NOT EXISTS total_shipping integer DEFAULT 0,
    ADD COLUMN IF NOT EXISTS total_discounts integer DEFAULT 0,
    ADD COLUMN IF NOT EXISTS source_platform text,
    ADD COLUMN IF NOT EXISTS source_name text,
    ADD COLUMN IF NOT EXISTS tags text[],
    ADD COLUMN IF NOT EXISTS cancelled_at timestamp with time zone,
    DROP COLUMN IF EXISTS customer_name,
    DROP COLUMN IF EXISTS customer_email,
    DROP COLUMN IF EXISTS payment_method;

-- Convert total_amount from numeric to integer (cents)
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS total_amount integer;
UPDATE public.orders SET total_amount = (total_amount_numeric * 100)::integer WHERE total_amount IS NULL;
ALTER TABLE public.orders DROP COLUMN total_amount_numeric;
ALTER TABLE public.orders ALTER COLUMN total_amount SET NOT NULL;
RAISE NOTICE 'Table "orders" altered successfully.';


-- =================================================================
-- Step 4: Data Migration - Move data from old structure to new
-- =================================================================
-- For each product in the `products` table, create a default variant
-- in `product_variants`, carrying over the SKU and other data.
DO $$
DECLARE
    prod RECORD;
BEGIN
    FOR prod IN SELECT p.id, p.company_id, i.sku as original_sku, i.quantity as original_quantity, i.price as original_price, i.cost as original_cost
               FROM public.products p
               JOIN public.inventory i ON p.external_product_id = i.external_product_id -- Assuming external_product_id links them
    LOOP
        IF NOT EXISTS (SELECT 1 FROM public.product_variants WHERE product_id = prod.id) THEN
            INSERT INTO public.product_variants (product_id, company_id, sku, title, price, cost, inventory_quantity, external_variant_id)
            VALUES (prod.id, prod.company_id, prod.original_sku, 'Default', (prod.original_price * 100)::integer, (prod.original_cost * 100)::integer, prod.original_quantity, prod.id::text);
            RAISE NOTICE 'Migrated product % to a default variant.', prod.id;
        END IF;
    END LOOP;
END $$;

-- Migrate old `sale_items` to `order_line_items`
DO $$
BEGIN
   IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sale_items') THEN
      INSERT INTO public.order_line_items (order_id, company_id, sku, product_name, quantity, price, cost_at_time)
      SELECT
          s.id,
          si.company_id,
          pv.sku,
          si.product_name,
          si.quantity,
          (si.unit_price * 100)::integer,
          (si.cost_at_time * 100)::integer
      FROM public.sale_items si
      JOIN public.orders s ON si.sale_id = s.id
      LEFT JOIN public.product_variants pv ON si.product_id = pv.product_id -- Simple link, might need adjustment
      WHERE NOT EXISTS (SELECT 1 FROM public.order_line_items oli WHERE oli.order_id = s.id);

      RAISE NOTICE 'Data migrated from sale_items to order_line_items.';
      DROP TABLE public.sale_items;
   END IF;
END $$;


-- =================================================================
-- Step 5: Add Foreign Keys and Constraints
-- =================================================================
ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS product_variants_product_id_fkey;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_product_id_fkey
    FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;

ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS product_variants_company_id_fkey;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_company_id_fkey
    FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

ALTER TABLE public.order_line_items DROP CONSTRAINT IF EXISTS order_line_items_order_id_fkey;
ALTER TABLE public.order_line_items ADD CONSTRAINT order_line_items_order_id_fkey
    FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;

-- Add other constraints safely
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS unique_order_number_per_company;
ALTER TABLE public.orders ADD CONSTRAINT unique_order_number_per_company UNIQUE (company_id, order_number);

ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS unique_sku_per_company;
ALTER TABLE public.product_variants ADD CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku);

RAISE NOTICE 'Constraints and foreign keys applied.';

-- =================================================================
-- Step 6: Create/Update Functions, Triggers, and RLS
-- =================================================================
-- Recreate functions and triggers to be safe.
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  new_company_id uuid;
  user_role TEXT;
BEGIN
  -- Create a new company for the new user
  INSERT INTO public.companies (name)
  VALUES (new.raw_user_meta_data->>'company_name')
  RETURNING id INTO new_company_id;

  -- Set the user's role to 'Owner'
  user_role := 'Owner';

  -- Update the user's app_metadata with the new company_id and role
  UPDATE auth.users
  SET raw_app_meta_data = jsonb_set(
    jsonb_set(COALESCE(raw_app_meta_data, '{}'::jsonb), '{company_id}', to_jsonb(new_company_id)),
    '{role}', to_jsonb(user_role)
  )
  WHERE id = new.id;
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
RAISE NOTICE 'Function handle_new_user() created.';

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
RAISE NOTICE 'Trigger on_auth_user_created created.';

-- RLS Helper function
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$ LANGUAGE sql STABLE;
RAISE NOTICE 'Function get_current_company_id() created.';

-- Loop to create RLS policies on all relevant tables
DO $$
DECLARE
    tbl_name text;
BEGIN
    FOR tbl_name IN
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name IN ('products', 'product_variants', 'orders', 'order_line_items', 'customers', 'suppliers', 'integrations')
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', tbl_name);
        EXECUTE format('DROP POLICY IF EXISTS "Users can only see their own company''s data." ON public.%I;', tbl_name);
        EXECUTE format(
            'CREATE POLICY "Users can only see their own company''s data." ON public.%I FOR ALL USING (company_id = public.get_current_company_id());',
            tbl_name
        );
        RAISE NOTICE 'RLS policy created for table %', tbl_name;
    END LOOP;
END $$;

RAISE NOTICE 'Database migration complete.';
