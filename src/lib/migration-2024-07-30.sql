-- Migration: Add soft delete to product_variants and update view
-- This script ensures that product variants can be soft-deleted and that
-- the primary inventory view respects these deletions.

BEGIN;

-- 1. Add 'deleted_at' column to product_variants
ALTER TABLE public.product_variants
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- 2. Create an index on the new column for performance
CREATE INDEX IF NOT EXISTS idx_product_variants_deleted_at ON public.product_variants (deleted_at);

-- 3. Re-create the main inventory view to filter out soft-deleted records from BOTH tables.
-- This ensures that variants of a deleted product, and individually deleted variants, are hidden.
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
  pv.id,
  pv.product_id,
  pv.company_id,
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
  pv.inventory_quantity,
  pv.location,
  pv.external_variant_id,
  pv.created_at,
  pv.updated_at,
  p.title AS product_title,
  p.status AS product_status,
  p.image_url,
  p.product_type
FROM
  public.product_variants pv
  JOIN public.products p ON pv.product_id = p.id
WHERE
  p.deleted_at IS NULL AND pv.deleted_at IS NULL;

-- 4. Grant usage to authenticated users
GRANT SELECT ON public.product_variants_with_details TO authenticated;


COMMIT;
