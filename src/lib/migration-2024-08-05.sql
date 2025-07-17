-- MIGRATION: 2024-08-05
-- This migration script corrects the column order in the product_variants_with_details view
-- to resolve the "cannot change name of view column" error.

-- Correct the view by ensuring the column order matches the original schema exactly.
-- This version correctly places `external_variant_id` before `location`.
CREATE OR REPLACE VIEW product_variants_with_details AS
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
    pv.location,             -- Corrected position
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type
FROM
    product_variants pv
JOIN
    products p ON pv.product_id = p.id
WHERE
    p.deleted_at IS NULL AND pv.deleted_at IS NULL;

-- Grant usage to the authenticated role
GRANT SELECT ON product_variants_with_details TO authenticated;
