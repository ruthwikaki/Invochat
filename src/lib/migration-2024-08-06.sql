-- Migration: 2024-08-06
-- This migration fixes the persistent column order error in the `product_variants_with_details` view
-- by dropping the view and recreating it with the correct column order and soft-delete logic.

-- Step 1: Drop the existing problematic view.
-- This is necessary to avoid PostgreSQL's column order restrictions on `CREATE OR REPLACE VIEW`.
DROP VIEW IF EXISTS public.product_variants_with_details;

-- Step 2: Recreate the view with the correct column order and soft-delete filters.
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
    pv.external_variant_id, -- Correct position
    pv.created_at,
    pv.updated_at,
    pv.location,             -- Correct position
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type
FROM
    product_variants pv
JOIN
    products p ON pv.product_id = p.id
WHERE
    p.deleted_at IS NULL AND pv.deleted_at IS NULL;

-- Grant usage and select permissions to the authenticated role
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON public.product_variants_with_details to authenticated;
