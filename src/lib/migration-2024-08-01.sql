-- MIGRATION SCRIPT: 2024-08-01
-- This script fixes an error in the previous migration by recreating the
-- product_variants_with_details view with the correct column order.

-- Recreate the view with the correct column order to avoid errors.
-- This version ensures that the column order matches the original view definition exactly,
-- only adding the product_type column at the end.
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
    pv.external_variant_id, -- Corrected position
    pv.created_at,
    pv.updated_at,
    pv.location, -- Corrected position
    pv.deleted_at,
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

-- Grant usage to the authenticated role
GRANT SELECT ON public.product_variants_with_details TO authenticated;
GRANT ALL ON public.product_variants_with_details TO service_role;
