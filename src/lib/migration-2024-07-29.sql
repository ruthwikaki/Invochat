-- Migration: Add Soft Deletes to Products and Variants (2024-07-29)
-- This script adds the deleted_at column to the products and product_variants tables
-- to enable soft deletion, preserving historical data integrity. It also updates
-- the main inventory view to exclude these soft-deleted records.

-- Step 1: Add the 'deleted_at' column to the 'products' table.
-- This allows products to be marked as deleted without removing them from the database,
-- which is crucial for maintaining historical order data.
ALTER TABLE public.products
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Step 2: Add the 'deleted_at' column to the 'product_variants' table.
-- This ensures that individual product variants can also be soft-deleted.
ALTER TABLE public.product_variants
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Step 3: Recreate the main inventory view to respect the new 'deleted_at' columns.
-- This is a key change to ensure that soft-deleted products and variants
-- no longer appear in the application's inventory lists and analytics.
DROP VIEW IF EXISTS public.product_variants_with_details;
CREATE OR REPLACE VIEW public.product_variants_with_details
AS
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
    p.title as product_title,
    p.status as product_status,
    p.image_url as image_url,
    p.product_type
FROM
    product_variants pv
JOIN
    products p ON pv.product_id = p.id
WHERE 
    p.deleted_at IS NULL AND pv.deleted_at IS NULL;

-- Step 4: Update the RLS policy on the products table to allow soft-deletion.
-- The existing policy only allows SELECT, but we need UPDATE permission for the 'deleted_at' field.
DROP POLICY IF EXISTS "Allow all access to own company data" ON public.products;
CREATE POLICY "Allow all access to own company data"
ON public.products
FOR ALL
USING (company_id = get_company_id());

-- Step 5: Update the RLS policy on the product_variants table for the same reason.
DROP POLICY IF EXISTS "Allow all access to own company data" ON public.product_variants;
CREATE POLICY "Allow all access to own company data"
ON public.product_variants
FOR ALL
USING (company_id = get_company_id());


-- Add a confirmation log
SELECT 'Migration 2024-07-29 (Soft Deletes) applied successfully.' as result;
