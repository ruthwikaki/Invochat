-- This script corrects the final discrepancy in the database schema.
-- It makes the `title` column on the `product_variants` table nullable
-- to correctly handle simple products from integrations like WooCommerce.
-- This operation is idempotent and safe to run multiple times.

-- Alter the column to allow NULL values.
ALTER TABLE public.product_variants
ALTER COLUMN title DROP NOT NULL;

-- Log that the final migration is complete.
DO $$
BEGIN
  RAISE NOTICE 'Database schema has been successfully updated to the final version.';
END $$;
